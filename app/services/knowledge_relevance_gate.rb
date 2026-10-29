# frozen_string_literal: true
require 'json'
require 'digest'

# Conservative, evidence-calibrated gate for the M2 synthetic browser pilot ONLY.
# It is not a probability model or a semantic entailment verifier.
# No cross-tenant search; operates solely on pre-authorized reranked hits.
class KnowledgeRelevanceGate
  POLICY_FILE = 'review/m2_relevance_gate_pilot_20261029.json'

  attr_reader :threshold

  def self.pilot
    config = JSON.parse(File.read(Rails.root.join(POLICY_FILE)))
    unless config['id'] == 'M2_RELEVANCE_PILOT_CONSERVATIVE_V1' &&
        config['status'] == 'EXPERIMENTAL_PILOT_NOT_PRODUCTION' &&
        config['algorithm'] == 'accept_chunk_if_raw_rerank_logit_at_least_threshold' &&
        config['embedding_model'] == ModalEmbeddingClient::MODEL_ID &&
        config['embedding_revision'] == ModalEmbeddingClient::MODEL_REVISION &&
        config['reranker_model'] == ModalRerankerClient::MODEL_ID &&
        config['reranker_revision'] == ModalRerankerClient::MODEL_REVISION
      raise IOError, 'invalid or unpinned M2 relevance policy'
    end
    new(config)
  rescue Errno::ENOENT, JSON::ParserError, TypeError
    raise IOError, 'M2 relevance policy unavailable or malformed'
  end

  def initialize(config)
    @config = config
    @threshold = config.fetch('threshold_logit')
    raise IOError, 'invalid calibrated cutoff' unless @threshold.is_a?(Numeric) && @threshold.finite?
  end

  # Check BEFORE a GPU request: any change to the approved corpus invalidates
  # the pilot calibration. Never silently reuse the threshold after editorial expansion.
  def validate!
    approved = KnowledgeArticleVersion.where(status: 'approved').order(:id).pluck(:id, :sha256)
    actual = Digest::SHA256.hexdigest(approved.to_json)
    expected_organizations = @config.fetch('organization_policy_versions')
    policy_versions = Organization.where(slug: expected_organizations.keys).order(:slug)
      .pluck(:slug, :policy_version).to_h
    unless approved.size == @config.fetch('approved_version_count') &&
        actual == @config.fetch('approved_versions_sha256') &&
        KnowledgeChunkEmbedding.count == @config.fetch('embedding_count') &&
        policy_versions == expected_organizations
      raise IOError, 'M2 relevance gate calibration stale for current approved corpus'
    end
    true
  end

  def filter(hits)
    raise ArgumentError, 'expected reranked hits' unless hits.is_a?(Array)
    hits.select do |hit|
      hit.rerank_score.is_a?(Numeric) && hit.rerank_score.finite? &&
        hit.rerank_score >= @threshold
    end
  end
end
