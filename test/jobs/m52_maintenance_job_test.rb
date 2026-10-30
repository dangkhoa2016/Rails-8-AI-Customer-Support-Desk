# frozen_string_literal: true
require 'test_helper'
require 'digest'

class M52MaintenanceJobTest < ActiveSupport::TestCase
  setup do
    @org = Organization.create!(slug: 'm52-test-maint', name: 'M52 Maint', vertical: 'b2b_saas', currency: 'USD')
    @member = Membership.create!(organization: @org,
      user: User.create!(email: 'm52-maint@example.test'), role: 'owner')
  end

  test 'expired queued request is removed without touching business records' do
    run = make_run
    run.update_columns(expires_at: 2.hours.ago)
    with_flag do
      before = [Ticket.count, TicketMessage.count, AuditEvent.count]
      MaintainAISearchRunsJob.new.perform
      assert_nil AISearchRun.find_by(id: run.id)
      assert_equal before, [Ticket.count, TicketMessage.count, AuditEvent.count]
    end
  end

  test 'stale running request is requeued for at most one bounded attempt' do
    run = make_run
    run.update_columns(status: 'running', attempts: 1, started_at: 14.minutes.ago)
    with_flag do
      previous = KnowledgeAISearchJob.queue_adapter
      KnowledgeAISearchJob.queue_adapter = :test
      MaintainAISearchRunsJob.new.perform
      assert_equal 'retrying', run.reload.status
      assert_equal 1, run.attempts
      assert_equal 'WORKER_STALE_REQUEUED', run.error_code
      assert_equal 1, KnowledgeAISearchJob.queue_adapter.enqueued_jobs.count
    ensure
      KnowledgeAISearchJob.queue_adapter = previous
    end
  end

  test 'stale exhausted search fails closed rather than using GPU' do
    run = make_run
    run.update_columns(status: 'running', attempts: 2, started_at: 14.minutes.ago)
    with_flag do
      MaintainAISearchRunsJob.new.perform
      assert_equal 'failed', run.reload.status
      assert_equal 'WORKER_STALE_EXHAUSTED', run.error_code
      assert_equal 2, run.attempts
    end
  end

  test 'maintenance is inert unless operator has enabled M5 async pilot' do
    run = make_run
    run.update_columns(expires_at: 2.hours.ago)
    before = ENV['M5_ASYNC_SEARCH_ENABLE']
    ENV['M5_ASYNC_SEARCH_ENABLE'] = 'NO'
    MaintainAISearchRunsJob.new.perform
    assert AISearchRun.exists?(id: run.id)
  ensure
    before ? ENV['M5_ASYNC_SEARCH_ENABLE'] = before : ENV.delete('M5_ASYNC_SEARCH_ENABLE')
  end

  private

  def make_run
    query = 'Synthetic billing knowledge question'
    AISearchRun.create!(organization: @org, membership: @member,
      request_role: 'owner', locale: 'en', query_text: query,
      query_sha256: Digest::SHA256.hexdigest(query))
  end

  def with_flag
    previous = ENV['M5_ASYNC_SEARCH_ENABLE']
    ENV['M5_ASYNC_SEARCH_ENABLE'] = 'YES'
    yield
  ensure
    previous ? ENV['M5_ASYNC_SEARCH_ENABLE'] = previous : ENV.delete('M5_ASYNC_SEARCH_ENABLE')
  end
end
