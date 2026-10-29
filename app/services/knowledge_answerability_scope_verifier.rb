# frozen_string_literal: true
require 'json'
require 'digest'

# Experimental scope-contrast check for synthetic staff-only M2 retrieval.
# Not a logical entailment/claim verifier; human approval remains mandatory.
# Does not search other organizations or alter the already approved KB.
class KnowledgeAnswerabilityScopeVerifier
  POLICY_FILE = 'review/m2_answerability_scope_policy_pilot_20261029.json'
  PROBES_FILE = 'review/m2_answerability_scope_probes_20261029.json'
  POLICY_ID = 'M2_SCOPE_CONTRAST_PILOT_V1'

  attr_reader :threshold

  def self.pilot
    config = JSON.parse(File.binread(Rails.root.join(POLICY_FILE)))
    raise IOError, 'untrusted scope policy' unless
      config['id'] == POLICY_ID &&
      config['status'] == 'EXPERIMENTAL_HUMAN_ASSIST_ONLY_NOT_ENTAILMENT' &&
      config['embedding_model'] == ModalEmbeddingClient::MODEL_ID &&
      config['embedding_revision'] == ModalEmbeddingClient::MODEL_REVISION &&
      config['reranker_model'] == ModalRerankerClient::MODEL_ID &&
      config['reranker_revision'] == ModalRerankerClient::MODEL_REVISION &&
      config['required_probe_count'] == 8 &&
      config['max_extra_reranker_calls_per_query'] == 1
    new(config)
  rescue Errno::ENOENT, JSON::ParserError, KeyError, TypeError
    raise IOError, 'scope policy unavailable or corrupt'
  end

  def initialize(config)
    @config = config
    @threshold = config.fetch('threshold_margin')
    raise IOError, 'invalid scope cutoff' unless @threshold.is_a?(Numeric) && @threshold.finite?
    bytes = File.binread(Rails.root.join(PROBES_FILE))
    raise IOError, 'scope probe provenance mismatch' unless
      Digest::SHA256.hexdigest(bytes) == config.fetch('probe_manifest_sha256')
    rows = JSON.parse(bytes).fetch('items')
    raise IOError, 'invalid scope probe cardinality' unless rows.size == 12
    @probes = {}
    rows.each do |row|
      key = [row.fetch('article_key'), row.fetch('locale')]
      raise IOError, 'duplicate scope key' if @probes.key?(key)
      documents = row.fetch('supported') + row.fetch('unsupported')
      raise IOError, 'invalid scope probes' unless row.fetch('supported').size == 4 &&
        row.fetch('unsupported').size == 4 &&
        documents.all? { |doc| doc.is_a?(String) && doc.valid_encoding? &&
          doc.bytesize.between?(12, 16_384) }
      @probes[key] = documents.freeze
    end
    @probes.freeze
  rescue Errno::ENOENT, JSON::ParserError, KeyError, TypeError
    raise IOError, 'scope probes unavailable or malformed'
  end

  # Preflight before embedding GPU: revalidate source, model and KB approval pin.
  def validate!(organization:, locale:)
    raise ArgumentError, 'untrusted tenant' unless organization.is_a?(Organization) && organization.persisted?
    raise ArgumentError, 'invalid locale' unless %w[vi en].include?(locale.to_s)
    raise IOError, 'relevance calibration changed' unless
      Digest::SHA256.file(Rails.root.join(KnowledgeRelevanceGate::POLICY_FILE)).hexdigest ==
        @config.fetch('relevance_policy_sha256')
    raise IOError, 'approval fingerprint changed' unless
      Digest::SHA256.hexdigest(KnowledgeArticleVersion.where(status:'approved')
        .order(:id).pluck(:id,:sha256).to_json) == @config.fetch('approved_versions_sha256') &&
      KnowledgeChunkEmbedding.count == @config.fetch('embedding_count') &&
      Organization.where(slug: @config.fetch('organization_policy_versions').keys)
        .order(:slug).pluck(:slug,:policy_version).to_h ==
        @config.fetch('organization_policy_versions')
    raise IOError, 'unsupported pilot tenant' unless %w[teamflow-cloud novamart-store].include?(organization.slug)
    true
  end

  # Called ONCE, after approved tenant/ACL-correct candidates are reranked.
  # The article must already be selected by the original tenant-filtered retrieval.
  def supports?(query:, hit:, locale:, organization:, reranker_client:)
    raise ArgumentError, 'invalid scope query' unless query.is_a?(String) &&
      query.valid_encoding? && query.bytesize.between?(1, 4_096)
    raise ArgumentError, 'invalid reranker pin' unless
      reranker_client.model_id == ModalRerankerClient::MODEL_ID &&
      reranker_client.model_revision == ModalRerankerClient::MODEL_REVISION
    row = KnowledgeArticle.where(organization_id:organization.id, article_key:hit.article_key).first
    raise SecurityError, 'scope article outside authorized tenant' if row.nil?
    documents = @probes.fetch([hit.article_key, locale.to_s]) { raise IOError, 'no scope contract for retrieved article' }
    scores = reranker_client.score(query:query, documents:documents)
    raise IOError, 'invalid scope verifier scores' unless scores.is_a?(Array) &&
      scores.size == 8 && scores.all? { |x| x.is_a?(Numeric) && x.finite? }
    (scores.first(4).max - scores.drop(4).max) >= @threshold
  end
end
