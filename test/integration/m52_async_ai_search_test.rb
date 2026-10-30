# frozen_string_literal: true
require 'test_helper'
require_relative '../support/csrf_requests'
require 'digest'

class M52AsyncAISearchTest < ActionDispatch::IntegrationTest
  include CsrfRequests

  setup do
    @org = Organization.create!(slug: 'teamflow-cloud', name: 'TeamFlow Cloud', vertical: 'b2b_saas', currency: 'USD')
    @other_org = Organization.create!(slug: 'novamart-store', name: 'NovaMart Store', vertical: 'ecommerce', currency: 'VND')
    @owner_user = User.create!(email: 'm52-owner@example.test')
    @member = Membership.create!(organization: @org, user: @owner_user, role: 'owner')
    @viewer = Membership.create!(organization: @org,
      user: User.create!(email: 'm52-viewer@example.test'), role: 'viewer')
    @other = Membership.create!(organization: @other_org,
      user: User.create!(email: 'm52-other@example.test'), role: 'owner')
  end

  test 'POST queues durable run and redirects without making a synchronous GPU call' do
    sign_in(@member)
    with_m52_env do
      job_original = KnowledgeAISearchJob.queue_adapter
      KnowledgeAISearchJob.queue_adapter = :test
      called = 0
      with_stubbed_retrieval(->(**_) { called += 1; raise 'synchronous GPU is forbidden' }) do
        post_with_csrf kb_ai_search_path, csrf_page: kb_ai_search_path,
          params: {query: 'Synthetic invoice activation question', privacy_confirmed: '1'}
      end
      assert_response :see_other
      assert_equal 0, called
      run = AISearchRun.last
      assert_equal @member.id, run.membership_id
      assert_equal @org.id, run.organization_id
      assert_equal 'queued', run.status
      assert_match(/\A[0-9a-f-]{36}\z/, run.public_id)
      assert_equal Digest::SHA256.hexdigest(run.query_text), run.query_sha256
      assert_equal 1, KnowledgeAISearchJob.queue_adapter.enqueued_jobs.count
      get kb_ai_search_path(run: run.public_id)
      assert_response :success
      assert_select "turbo-frame#ai_search_run_#{run.public_id}", 1
      assert_select '[data-ai-terminal=false]', 1
      assert_select "turbo-frame#ai_search_run_#{run.public_id}[src]", 1
    ensure
      KnowledgeAISearchJob.queue_adapter = job_original
    end
  end

  test 'frame status is private to exact tenant and membership and cannot reveal cross-tenant results' do
    run = make_run
    with_m52_env do
      sign_in(@other)
      get kb_ai_search_run_path(run.public_id),
        headers: {'Turbo-Frame' => "ai_search_run_#{run.public_id}"}
      assert_response :not_found
      sign_in(@viewer)
      get kb_ai_search_run_path(run.public_id),
        headers: {'Turbo-Frame' => "ai_search_run_#{run.public_id}"}
      assert_response :forbidden
      sign_in(@member)
      get kb_ai_search_run_path(run.public_id),
        headers: {'Turbo-Frame' => "ai_search_run_#{run.public_id}"}
      assert_response :success
      assert_select "turbo-frame#ai_search_run_#{run.public_id}", 1
      assert_select 'script', text: /MODAL_PROXY_SECRET/, count: 0
    end
  end

  test 'query with PII and missing attestation cannot create a queued run' do
    sign_in(@member)
    with_m52_env do
      post_with_csrf kb_ai_search_path, csrf_page: kb_ai_search_path,
        params: {query: 'Send to human@example.com now', privacy_confirmed: '1'}
      assert_response :unprocessable_entity
      post_with_csrf kb_ai_search_path, csrf_page: kb_ai_search_path,
        params: {query: 'Synthetic billing activation question'}
      assert_response :unprocessable_entity
      assert_equal 0, AISearchRun.count
    end
  end

  test 'job persists approved scoped citations and never writes business tables' do
    source = create_source
    run = make_run
    with_m52_env do
      callback = ->(**_) {
        [KnowledgeRerankedRetrieval::Result.new(
          article_key: source.knowledge_article.article_key,
          article_version_id: source.id, chunk_index: 0,
          content: source.body, citation: 'TF-M52-001@en:v1#chunk-0',
          policy_refs: [], sha256: Digest::SHA256.hexdigest(source.body),
          locale: 'en', cosine_distance: 0.17, rerank_score: 4.2)]
      }
      before = [Ticket.count, TicketMessage.count, AuditEvent.count]
      with_stubbed_retrieval(callback) { KnowledgeAISearchJob.new.perform(run.id) }
      assert_equal 'succeeded', run.reload.status
      assert_equal 1, run.attempts
      assert_equal 1, run.safe_hits.length
      assert_equal 'TF-M52-001', run.safe_hits.first.article_key
      assert_equal before, [Ticket.count, TicketMessage.count, AuditEvent.count]
      sign_in(@member)
      get kb_ai_search_run_path(run.public_id),
        headers: {'Turbo-Frame' => "ai_search_run_#{run.public_id}"}
      assert_response :success
      assert_select 'article.ai-hit', 1
      assert_select '[data-ai-terminal=true]', 1
    end
  end

  test 'transient Modal HTTP 500 retries at most once and fails closed on second failure' do
    run = make_run
    with_m52_env do
      prior = KnowledgeAISearchJob.queue_adapter
      KnowledgeAISearchJob.queue_adapter = :test
      with_stubbed_retrieval(->(**_) { raise IOError, 'Modal reranker HTTP 500' }) do
        KnowledgeAISearchJob.new.perform(run.id)
        assert_equal 'retrying', run.reload.status
        assert_equal 1, run.attempts
        assert_equal 1, KnowledgeAISearchJob.queue_adapter.enqueued_jobs.length
        KnowledgeAISearchJob.new.perform(run.id)
      end
      assert_equal 'failed', run.reload.status
      assert_equal 2, run.attempts
      assert_equal 'MODAL_RETRY_EXHAUSTED', run.error_code
      assert_equal [], run.result_hits
      assert_equal 1, KnowledgeAISearchJob.queue_adapter.enqueued_jobs.length
    ensure
      KnowledgeAISearchJob.queue_adapter = prior
    end
  end

  test 'revoked membership fails before calling any GPU' do
    run = make_run
    @member.update!(role: 'viewer')
    with_m52_env do
      with_stubbed_retrieval(->(**_) { raise 'GPU should not be called' }) do
        KnowledgeAISearchJob.new.perform(run.id)
      end
      assert_equal 'failed', run.reload.status
      assert_equal 'AUTH_REVOKED', run.error_code
      assert_equal 0, run.attempts
    end
  end

  test 'expired request is hidden and never processed' do
    run = make_run
    run.update_columns(expires_at: 1.minute.ago)
    with_m52_env do
      with_stubbed_retrieval(->(**_) { raise 'GPU should not be called' }) do
        KnowledgeAISearchJob.new.perform(run.id)
      end
      assert_equal 'queued', run.reload.status
      sign_in(@member)
      get kb_ai_search_run_path(run.public_id)
      assert_response :not_found
    end
  end

  private

  def sign_in(member)
    post_with_csrf demo_sign_in_path, csrf_page: demo_sign_in_path,
      params: {membership_id: member.id, locale: 'en'}
    assert_redirected_to root_path
  end

  def with_m52_env
    vars = {
      'M5_ASYNC_SEARCH_ENABLE' => 'YES', 'M2_SEMANTIC_UI_ENABLE' => 'YES',
      'M2_ANSWERABILITY_SCOPE_ENABLE' => 'NO',
      'MODAL_EMBEDDING_URL' => 'https://synthetic-embed.us-east.modal.run/embed',
      'MODAL_EMBEDDING_TOKEN' => 'e' * 32,
      'MODAL_RERANK_URL' => 'https://synthetic-rerank.us-east.modal.run/rerank',
      'MODAL_RERANK_TOKEN' => 'r' * 32,
      'MODAL_PROXY_KEY' => 'wk-' + 'k' * 28,
      'MODAL_PROXY_SECRET' => 'ws-' + 's' * 28
    }
    previous = vars.to_h { |key, _| [key, ENV[key]] }
    vars.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous&.each { |key, value| value ? ENV[key] = value : ENV.delete(key) }
  end

  def make_run
    text = 'Synthetic invoice activation question'
    AISearchRun.create!(organization: @org, membership: @member, request_role: 'owner',
      locale: 'en', query_text: text, query_sha256: Digest::SHA256.hexdigest(text))
  end

  def create_source
    article = KnowledgeArticle.create!(organization: @org, article_key: 'TF-M52-001',
      category: 'billing', audience: 'public', policy_refs: [])
    body = 'Verify invoice payment and workspace activation status.'
    KnowledgeArticleVersion.create!(organization: @org, knowledge_article: article,
      locale: 'en', version_number: 1, title: 'Synthetic activation',
      body: body, sha256: Digest::SHA256.hexdigest(body),
      policy_version: @org.policy_version, source_blueprint_sha256: 'synthetic-m52-test',
      effective_from: Date.yesterday, status: 'approved', approved_by: @owner_user.id,
      approved_at: Time.current)
  end

  def with_stubbed_retrieval(callback)
    original = KnowledgeRerankedRetrieval.method(:search)
    KnowledgeRerankedRetrieval.define_singleton_method(:search, &callback)
    yield
  ensure
    KnowledgeRerankedRetrieval.define_singleton_method(:search, original)
  end
end
