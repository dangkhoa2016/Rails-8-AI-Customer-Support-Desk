# frozen_string_literal: true
require 'digest'
require 'benchmark'
require 'net/http'

# Only a dedicated Solid Queue worker performs long-running Modal calls.
# No customer-facing writes; no unreviewed queries or cross-tenant KB.
class KnowledgeAISearchJob < ApplicationJob
  queue_as :m5_ai
  MAX_ATTEMPTS = 2
  STALE_AFTER = 12.minutes
  RETRY_DELAY = 8.seconds

  def perform(run_id)
    return unless (Rails.env.development? || Rails.env.test?) && ENV['M5_ASYNC_SEARCH_ENABLE'] == 'YES'
    return unless ENV['M2_SEMANTIC_UI_ENABLE'] == 'YES'
    return if ENV['M2_ANSWERABILITY_SCOPE_ENABLE'] == 'YES'
    return if KnowledgeScopePreviewGate.eligible?

    run = AISearchRun.find_by(id: run_id)
    return unless run && !run.expired? && !run.terminal?
    return mark_failure(run, 'AUTH_REVOKED') unless authorized?(run)
    return mark_failure(run, 'INVALID_INPUT') unless valid_synthetic_query?(run.query_text) &&
      Digest::SHA256.hexdigest(run.query_text) == run.query_sha256
    # Prevent concurrent duplicate jobs. A preempted worker can be reclaimed only
    # after an explicit stale timeout, with at most two total attempts.
    eligible = AISearchRun.where(id: run.id, status: %w[queued retrying])
    eligible = AISearchRun.where(id: run.id, status: 'running')
      .where('started_at < ?', STALE_AFTER.ago) if run.status == 'running'
    return if run.attempts >= MAX_ATTEMPTS
    count = eligible.update_all(status: 'running', started_at: Time.current,
      attempts: run.attempts + 1, updated_at: Time.current)
    return unless count == 1
    run.reload
    begin
      hits = nil
      elapsed = (Benchmark.realtime do
        hits = KnowledgeRerankedRetrieval.search(
          organization: run.organization, role: run.request_role, query: run.query_text,
          locale: run.locale, embedding_client: ModalEmbeddingClient.new,
          reranker_client: ModalRerankerClient.new, candidate_limit: 12, limit: 5,
          query_privacy_reviewed: true, relevance_gate: KnowledgeRelevanceGate.pilot,
          answerability_verifier: nil
        )
      end * 1000).round
      raise SecurityError, 'tenant drift' unless authorized?(run)
      verified = hits.map { |hit| persistable_hit(run, hit) }
      AISearchRun.where(id: run.id, status: 'running', attempts: run.attempts)
        .update_all(status: 'succeeded', result_hits: verified, elapsed_ms: elapsed,
          error_code: nil, finished_at: Time.current, updated_at: Time.current)
    rescue StandardError => error
      # NEVER log the exception message: remote errors may include URLs or tokens.
      transient = transient?(error)
      if transient && run.attempts < MAX_ATTEMPTS && !run.expired? && authorized?(run)
        run.update_columns(status: 'retrying', error_code: 'MODAL_TRANSIENT',
          updated_at: Time.current)
        begin
          self.class.set(wait: RETRY_DELAY).perform_later(run.id)
        rescue StandardError
          mark_failure(run, 'QUEUE_UNAVAILABLE')
        end
      else
        mark_failure(run, transient ? 'MODAL_RETRY_EXHAUSTED' : 'RETRIEVAL_UNAVAILABLE')
      end
    rescue SecurityError
      mark_failure(run, 'AUTH_OR_PROVENANCE')
    end
  end

  private

  def authorized?(run)
    member = Membership.find_by(id: run.membership_id, organization_id: run.organization_id)
    member && %w[owner admin agent].include?(member.role) &&
      member.role == run.request_role && run.organization.persisted?
  end

  def valid_synthetic_query?(query)
    query.is_a?(String) && query.valid_encoding? && query.length.between?(12, 300) &&
      !query.match?(/https?:\/\/|www\.|[\w.+-]+@[\w.-]+\.[a-z]{2,}/i) &&
      !query.match?(/(?:\+?\d[\d\s().-]{7,}\d)/) &&
      !query.include?(10.chr) && !query.include?(13.chr)
  end

  def transient?(error)
    return true if error.is_a?(Net::ReadTimeout) || error.is_a?(Net::OpenTimeout) ||
      error.is_a?(Timeout::Error) || error.is_a?(Errno::ECONNRESET)
    error.is_a?(IOError) && error.message.match?(/\bHTTP (429|500|502|503|504)\b/)
  end

  def persistable_hit(run, hit)
    raise SecurityError, 'invalid tenant/locale hit' unless hit.is_a?(KnowledgeRerankedRetrieval::Result) &&
      hit.locale == run.locale && hit.article_key.start_with?(
        run.organization.slug == 'teamflow-cloud' ? 'TF-' : 'NM-')
    version = KnowledgeArticleVersion.includes(:knowledge_article).find_by(
      id: hit.article_version_id, organization_id: run.organization_id)
    article = version&.knowledge_article
    raise SecurityError, 'unapproved or cross-tenant source' unless version && article &&
      article.article_key == hit.article_key && version.active_on? &&
      article.organization_id == run.organization_id && %w[public agent].include?(article.audience) &&
      version.locale == run.locale && version.policy_version == run.organization.policy_version
    raise SecurityError, 'chunk digest mismatch' unless
      Digest::SHA256.hexdigest(hit.content) == hit.sha256
    {
      article_key: hit.article_key, article_version_id: hit.article_version_id,
      chunk_index: hit.chunk_index, content: hit.content,
      citation: hit.citation, policy_refs: hit.policy_refs, sha256: hit.sha256,
      locale: hit.locale, cosine_distance: hit.cosine_distance, rerank_score: hit.rerank_score
    }
  end

  def mark_failure(run, code)
    AISearchRun.where(id: run.id).where.not(status: 'succeeded')
      .update_all(status: 'failed', error_code: code, result_hits: [],
        finished_at: Time.current, updated_at: Time.current)
  end
end
