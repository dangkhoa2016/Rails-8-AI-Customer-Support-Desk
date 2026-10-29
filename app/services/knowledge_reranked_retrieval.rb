# frozen_string_literal: true
require 'digest'

# Stage 1: tenant- and ACL-filtered Qwen3-Embedding-4B cosine candidates.
# Stage 2: Qwen3-Reranker-4B logits for EXACTLY those authorized candidates.
# No LLM writes, business changes, or cross-tenant candidate export.
class KnowledgeRerankedRetrieval
  Result = Struct.new(:article_key, :article_version_id, :chunk_index, :content,
    :citation, :policy_refs, :sha256, :locale, :cosine_distance, :rerank_score,
    keyword_init: true)

  def self.search(organization:, role:, query:, locale:, embedding_client:, reranker_client:,
                  as_of: Date.current, candidate_limit: 12, limit: 5, query_privacy_reviewed: false,
                  relevance_gate: nil, answerability_verifier: nil)
    raise ArgumentError, 'untrusted tenant' unless organization.is_a?(Organization) && organization.persisted?
    raise ArgumentError, 'invalid role' unless %w[customer viewer agent admin owner].include?(role.to_s)
    raise ArgumentError, 'invalid locale' unless %w[vi en].include?(locale.to_s)
    raise ArgumentError, 'invalid date' unless as_of.is_a?(Date)
    raise SecurityError, 'query must be reviewed for private information before sending to Modal' unless
      query_privacy_reviewed == true
    raise ArgumentError, 'query invalid' unless query.is_a?(String) && query.valid_encoding? &&
      !query.strip.empty? && query.bytesize <= 4_096
    raise ArgumentError, 'invalid retrieval limits' unless candidate_limit.to_i.between?(1, 12) &&
      limit.to_i.between?(1, candidate_limit.to_i)
    raise ArgumentError, 'mismatched embedding model' unless
      embedding_client.model_id == ModalEmbeddingClient::MODEL_ID &&
      embedding_client.model_revision == ModalEmbeddingClient::MODEL_REVISION
    raise ArgumentError, 'mismatched reranker model' unless
      reranker_client.model_id == ModalRerankerClient::MODEL_ID &&
      reranker_client.model_revision == ModalRerankerClient::MODEL_REVISION

    # Fail closed BEFORE spending GPU if the calibrated corpus/model has changed.
    relevance_gate&.validate!
    answerability_verifier&.validate!(organization: organization, locale: locale)
    raise ArgumentError, 'scope verifier requires relevance gate' if answerability_verifier && !relevance_gate
    vector = embedding_client.embed_query(query)
    candidates = KnowledgeSemanticRetrieval.search(
      organization: organization, role: role, embedding: vector,
      model_id: embedding_client.model_id, model_revision: embedding_client.model_revision,
      locale: locale, as_of: as_of, limit: candidate_limit
    )
    return [] if candidates.empty?

    # Re-check approval, tenant, audience, validity and actual digest just before
    # transmitting only approved synthetic KB text to Modal for reranking.
    ids = candidates.map(&:article_version_id)
    versions = KnowledgeArticleVersion.where(organization_id: organization.id, id: ids)
      .includes(:knowledge_article).index_by(&:id)
    audience = %w[agent admin owner].include?(role.to_s) ? %w[public agent] : ['public']
    candidates.each do |candidate|
      v = versions.fetch(candidate.article_version_id)
      article = v.knowledge_article
      raise SecurityError, 'KB authorization drift before rerank' unless
        v.active_on?(as_of) && v.policy_version == organization.policy_version &&
        article.organization_id == organization.id && audience.include?(article.audience) &&
        v.locale == locale.to_s &&
        Digest::SHA256.hexdigest(candidate.content) == candidate.sha256
    end

    scores = reranker_client.score(query: query, documents: candidates.map(&:content))
    raise IOError, 'unexpected reranker score count' unless
      scores.is_a?(Array) && scores.size == candidates.size &&
      scores.all? { |n| n.is_a?(Numeric) && n.finite? }

    ranked = candidates.each_with_index.map do |candidate, idx|
      Result.new(**candidate.to_h, rerank_score: scores[idx])
    end.sort_by { |hit| [-hit.rerank_score, hit.cosine_distance, hit.citation] }
    qualified = relevance_gate ? relevance_gate.filter(ranked) : ranked
    return qualified.first(limit.to_i) unless answerability_verifier && qualified.any?

    # One and only one additional Reranker-4B call; fail closed on unsupported
    # multi-intent requests. Never pull in another tenant's KB for verification.
    best = qualified.first
    return [] unless answerability_verifier.supports?(query: query, hit: best,
      locale: locale, organization: organization, reranker_client: reranker_client)

    # Only display evidence from the article whose scope was checked.
    qualified.select { |hit| hit.article_key == best.article_key }.first(limit.to_i)
  end
end
