# frozen_string_literal: true
# EXPERIMENT ONLY: caller-supplied atomic claims. This class does NOT split
# questions, prove logical entailment, or generate policy/customer answers.
# Every returned citation MUST be reviewed and approved by a human agent.
class KnowledgeClaimEvidencePilot
  Claim = Struct.new(:id, :text, keyword_init: true)
  MAX_CLAIMS = 3
  MAX_CLAIM_BYTES = 900

  def self.evaluate(organization:, role:, locale:, claims:, embedding_client:,
                    reranker_client:, privacy_reviewed: false,
                    relevance_gate: KnowledgeRelevanceGate.pilot,
                    scope_verifier: KnowledgeAnswerabilityScopeVerifier.pilot)
    raise SecurityError, 'explicit human privacy review required' unless privacy_reviewed == true
    raise ArgumentError, 'unknown tenant' unless organization.is_a?(Organization) &&
      organization.persisted? && %w[teamflow-cloud novamart-store].include?(organization.slug)
    raise ArgumentError, 'staff-only pilot' unless %w[agent admin owner].include?(role.to_s)
    raise ArgumentError, 'invalid locale' unless %w[vi en].include?(locale.to_s)
    raise ArgumentError, 'manual atomic claims required' unless claims.is_a?(Array) &&
      claims.size.between?(1, MAX_CLAIMS) && claims.all? { |c| c.is_a?(Claim) }
    raise ArgumentError, 'invalid model clients' unless
      embedding_client.model_id == ModalEmbeddingClient::MODEL_ID &&
      embedding_client.model_revision == ModalEmbeddingClient::MODEL_REVISION &&
      reranker_client.model_id == ModalRerankerClient::MODEL_ID &&
      reranker_client.model_revision == ModalRerankerClient::MODEL_REVISION

    seen = {}
    claims.each do |claim|
      raise ArgumentError, 'invalid claim ID' unless claim.id.is_a?(String) &&
        claim.id.match?(/\A[a-zA-Z0-9_-]{1,80}\z/) && !seen[claim.id]
      seen[claim.id] = true
      txt = claim.text
      raise ArgumentError, 'invalid claim text' unless txt.is_a?(String) &&
        txt.valid_encoding? && txt.bytesize.between?(12, MAX_CLAIM_BYTES) &&
        !txt.include?("\n") && !txt.include?("\r")
      raise SecurityError, 'claim may contain private data' if txt.match?(
        %r{https?://|www\.|[\w.+-]+@[\w.-]+\.[a-z]{2,}}i
      ) || txt.match?(/(?:\+?\d[\d\s().-]{7,}\d)/)
    end

    # Corpus and models fail closed BEFORE any external GPU requests.
    relevance_gate.validate!
    scope_verifier.validate!(organization: organization, locale: locale)

    results = claims.map do |claim|
      # Original retrieval already checks tenant, approval, ACL, locale,
      # policy, validity dates and exact content digest before Modal.
      raw = KnowledgeRerankedRetrieval.search(
        organization: organization, role: role, query: claim.text, locale: locale,
        embedding_client: embedding_client, reranker_client: reranker_client,
        candidate_limit: 12, limit: 12, query_privacy_reviewed: true
      )
      relevant = relevance_gate.filter(raw).first(5)
      verified = relevant.any? && scope_verifier.supports?(
        query: claim.text, hit: relevant.first, locale: locale,
        organization: organization, reranker_client: reranker_client
      )
      hits = verified ?
        relevant.select { |candidate| candidate.article_key == relevant.first.article_key }.first(5) : []
      {
        claim_id: claim.id,
        claim_sha256: Digest::SHA256.hexdigest(claim.text),
        status: hits.any? ? 'evidence_candidate_human_review_required' : 'abstain_no_qualified_evidence',
        # Scores are ranking signals, not entailment probabilities.
        baseline_candidate: relevant.any?,
        raw_top1: raw.first&.article_key,
        raw_top1_logit: raw.first&.rerank_score,
        scope_checked: relevant.any?,
        citations: hits.map { |hit| {
          article_key: hit.article_key, citation: hit.citation,
          article_version_id: hit.article_version_id,
          content_sha256: hit.sha256, raw_logit: hit.rerank_score
        } }
      }
    end
    qualified = results.count { |r| r[:status] == 'evidence_candidate_human_review_required' }
    {
      state: qualified == 0 ? 'no_candidates' :
        (qualified == results.size ? 'all_have_candidates' : 'partial_candidates'),
      decision: 'NO_AUTONOMOUS_ANSWER_HUMAN_REVIEW_REQUIRED',
      claim_count: claims.size, candidate_count: qualified,
      model_requests_maximum: claims.size * 3,
      results: results
    }
  end
end
