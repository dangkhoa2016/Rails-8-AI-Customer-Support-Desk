# frozen_string_literal: true
require 'test_helper'
require_relative '../support/csrf_requests'

class KnowledgeAiSearchUiTest < ActionDispatch::IntegrationTest
  include CsrfRequests

  setup do
    @org = Organization.create!(slug: 'ai-search-tf', name: 'AI Search Demo', vertical: 'b2b_saas', currency: 'USD')
    @other = Organization.create!(slug: 'ai-search-nm', name: 'Other Tenant', vertical: 'ecommerce', currency: 'VND')
    @agent = Membership.create!(organization: @org, user: User.create!(email: 'ai-agent@example.test'), role: 'agent')
    @viewer = Membership.create!(organization: @org, user: User.create!(email: 'ai-viewer@example.test'), role: 'viewer')
    @other_agent = Membership.create!(organization: @other, user: User.create!(email: 'ai-other@example.test'), role: 'agent')
  end

  test 'must have authenticated synthetic membership' do
    get kb_ai_search_path
    assert_redirected_to demo_sign_in_path
  end

  test 'viewer is forbidden and cannot invoke AI' do
    sign_in(@viewer)
    get kb_ai_search_path
    assert_response :forbidden
    post_with_csrf kb_ai_search_path, csrf_page: root_path, params: {query: 'Synthetic knowledge question 123', privacy_confirmed: '1'}
    assert_response :forbidden
  end

  test 'default off hides active GPU search' do
    sign_in(@agent)
    get kb_ai_search_path
    assert_response :success
    assert_select 'form[action="/kb/ai-search"]'
    assert_select 'input[type=submit][disabled]', 1
    assert_match(/disabled/, response.body)
    assert_includes response.headers['Cache-Control'], 'no-store'
    post_with_csrf kb_ai_search_path, csrf_page: kb_ai_search_path, params: {query: 'Synthetic KB search question', privacy_confirmed: '1'}
    assert_response :service_unavailable
  end

  test 'privacy confirmation required and PII markers rejected before GPU client instantiation' do
    sign_in(@agent)
    with_live_config do
      post_with_csrf kb_ai_search_path, csrf_page: kb_ai_search_path, params: {query: 'Synthetic invoice activation question'}
      assert_response :unprocessable_entity
      post_with_csrf kb_ai_search_path, csrf_page: kb_ai_search_path, params: {query: 'Please email customer@example.com for records', privacy_confirmed: '1'}
      assert_response :unprocessable_entity
      post_with_csrf kb_ai_search_path, csrf_page: kb_ai_search_path, params: {query: 'Use number +84 091 223 4567 for customer', privacy_confirmed: '1'}
      assert_response :unprocessable_entity
    end
  end

  test 'authorized agent gets read-only ranked citations from current tenant and language' do
    sign_in(@agent)
    with_live_config do
      hit = KnowledgeRerankedRetrieval::Result.new(article_key: 'TF-AI-001', article_version_id: 1,
        chunk_index: 0, content: '<script>alert("xss")</script> approved evidence',
        citation: 'TF-AI-001@en:v2#chunk-0', policy_refs: [], sha256: 'a' * 64,
        locale: 'en', cosine_distance: 0.13, rerank_score: 4.25)
      KnowledgeArticle.create!(organization: @org, article_key: 'TF-AI-001', category: 'demo', audience: 'public', policy_refs: [])
      captured = nil
      callback = ->(**opts) { captured = opts; [hit] }
      with_stubbed_search(callback) do
        post_with_csrf kb_ai_search_path, csrf_page: kb_ai_search_path,
          params: {query: 'Synthetic billing activation question', privacy_confirmed: '1'}
      end
      assert_response :success
      assert_equal @org.id, captured[:organization].id
      assert_equal 'agent', captured[:role]
      assert_equal 'en', captured[:locale]
      assert_equal true, captured[:query_privacy_reviewed]
      assert_select 'article.ai-hit', 1
      assert_select 'a[href*="knowledge_articles"]', text: 'TF-AI-001'
      # Importmap and Turbo legitimately add script tags; reject only user-controlled script content.
      assert_select 'script', text: /alert\(\"xss\"\)/, count: 0
      assert_includes response.body, '&lt;script&gt;'
      assert_includes response.headers['Cache-Control'], 'no-store'
    end
  end

  test 'failed sealed challenge blocks requested experimental scope preview before GPU' do
    sign_in(@agent)
    previous = ENV['M2_ANSWERABILITY_SCOPE_ENABLE']
    ENV['M2_ANSWERABILITY_SCOPE_ENABLE'] = 'YES'
    with_live_config do
      calls = 0
      with_stubbed_search(->(**_opts) { calls += 1; [] }) do
        post_with_csrf kb_ai_search_path, csrf_page: kb_ai_search_path,
          params: {query: 'Synthetic billing support question', privacy_confirmed: '1'}
      end
      assert_response :service_unavailable
      assert_equal 0, calls
      assert_includes response.body, 'sealed 80-query evaluation did not meet'
      assert_select 'input[type=submit][disabled]', 1
    end
  ensure
    previous ? ENV['M2_ANSWERABILITY_SCOPE_ENABLE'] = previous : ENV.delete('M2_ANSWERABILITY_SCOPE_ENABLE')
  end

  test 'zero qualified evidence shows tenant-scoped abstention instead of unrelated Top-5' do
    sign_in(@other_agent)
    with_live_config do
      with_stubbed_search(->(**_opts) { [] }) do
        post_with_csrf kb_ai_search_path, csrf_page: kb_ai_search_path,
          params: {query: 'Synthetic SaaS activation question', privacy_confirmed: '1'}
      end
      assert_response :success
      assert_select 'article.ai-hit', 0
      assert_select 'p[role="status"]', 1
      assert_includes response.body, 'Other Tenant'
      assert_includes response.body, 'No sufficiently supported KB evidence'
    end
  end

  test 'session budget rejects repeated submissions without new model requests' do
    sign_in(@other_agent)
    with_live_config do
      calls = 0
      callback = ->(**opts) { calls += 1; [] }
      with_stubbed_search(callback) do
        2.times do
          post_with_csrf kb_ai_search_path, csrf_page: kb_ai_search_path,
            params: {query: 'Synthetic warranty issue on day fourteen', privacy_confirmed: '1'}
        end
      end
      assert_response :too_many_requests
      assert_equal 1, calls
    end
  end

  test 'tenant-specific examples never suggest another business domain in VI and EN' do
    {
      'teamflow-cloud' => {
        'vi' => ['Hóa đơn đã thanh toán', '499.999 đồng'],
        'en' => ['My invoice is paid', 'VND 499,999']
      },
      'novamart-store' => {
        'vi' => ['499.999 đồng', 'Hóa đơn đã thanh toán'],
        'en' => ['VND 499,999', 'My invoice is paid']
      }
    }.each do |slug, languages|
      @org.update!(slug: slug, name: slug)
      sign_in(@agent)
      languages.each do |locale, pair|
        get kb_ai_search_path(locale: locale)
        assert_response :success
        assert_includes response.body, pair.first
        refute_includes response.body, pair.last
        assert_select 'a[href*="demo/sign_in"]'
        assert_select 'textarea[placeholder]', 1
        assert_includes response.body, slug
      end
    end
  end

  test 'unknown tenant has no hard-coded suggestions from TeamFlow or NovaMart' do
    sign_in(@agent)
    get kb_ai_search_path(locale: 'vi')
    assert_response :success
    assert_select '.ai-examples code', 0
    refute_includes response.body, 'Hóa đơn đã thanh toán nhưng gói chưa kích hoạt'
  end

  private

  def sign_in(member)
    post_with_csrf demo_sign_in_path, csrf_page: demo_sign_in_path,
      params: {membership_id: member.id, locale: 'en'}
    assert_redirected_to root_path
  end

  def with_stubbed_search(callback)
    original = KnowledgeRerankedRetrieval.method(:search)
    KnowledgeRerankedRetrieval.define_singleton_method(:search, &callback)
    yield
  ensure
    KnowledgeRerankedRetrieval.define_singleton_method(:search, original)
  end

  def with_live_config
    names = %w[M2_SEMANTIC_UI_ENABLE MODAL_EMBEDDING_URL MODAL_EMBEDDING_TOKEN MODAL_RERANK_URL MODAL_RERANK_TOKEN MODAL_PROXY_KEY MODAL_PROXY_SECRET]
    previous = names.to_h { |name| [name, ENV[name]] }
    ENV['M2_SEMANTIC_UI_ENABLE'] = 'YES'
    ENV['MODAL_EMBEDDING_URL'] = 'https://fake-embedding.us-east.modal.run/embed'
    ENV['MODAL_EMBEDDING_TOKEN'] = 'x' * 32
    ENV['MODAL_RERANK_URL'] = 'https://fake-rerank.us-east.modal.run/rerank'
    ENV['MODAL_RERANK_TOKEN'] = 'y' * 32
    ENV['MODAL_PROXY_KEY'] = 'wk-' + 'k' * 28
    ENV['MODAL_PROXY_SECRET'] = 'ws-' + 's' * 28
    yield
  ensure
    previous&.each { |name, value| value ? ENV[name] = value : ENV.delete(name) }
  end
end
