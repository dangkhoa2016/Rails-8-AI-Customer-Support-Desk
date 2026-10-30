# frozen_string_literal: true
# M5.2 scheduled housekeeping. No GPU, customer writes or raw query logging.
class MaintainAISearchRunsJob < ApplicationJob
  queue_as :m5_ai

  def perform
    return unless (Rails.env.development? || Rails.env.test?) &&
      ENV['M5_ASYNC_SEARCH_ENABLE'] == 'YES'
    now = Time.current
    # Never delete a running search until the attempt has completed or timed out.
    AISearchRun.where(status: %w[queued retrying succeeded failed])
      .where('expires_at < ?', now).delete_all

    # Recover workers terminated without application exception handling.
    # Distinct from the normal transient Modal error retry in KnowledgeAISearchJob.
    AISearchRun.where(status: 'running')
      .where('started_at < ?', KnowledgeAISearchJob::STALE_AFTER.ago)
      .find_each do |run|
      if run.expired? || run.attempts >= KnowledgeAISearchJob::MAX_ATTEMPTS
        AISearchRun.where(id: run.id, status: 'running').update_all(
          status: 'failed', error_code: 'WORKER_STALE_EXHAUSTED',
          finished_at: now, updated_at: now)
        next
      end
      claimed = AISearchRun.where(id: run.id, status: 'running')
        .where('started_at < ?', KnowledgeAISearchJob::STALE_AFTER.ago)
        .update_all(status: 'retrying', error_code: 'WORKER_STALE_REQUEUED',
          updated_at: now)
      next unless claimed == 1
      begin
        KnowledgeAISearchJob.perform_later(run.id)
      rescue StandardError
        AISearchRun.where(id: run.id, status: 'retrying').update_all(
          status: 'failed', error_code: 'QUEUE_UNAVAILABLE',
          finished_at: now, updated_at: now)
      end
    end
  end
end
