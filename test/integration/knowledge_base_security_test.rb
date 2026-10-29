# frozen_string_literal: true
require 'test_helper'
require_relative '../support/csrf_requests'
require 'digest'

class KnowledgeBaseSecurityTest < ActionDispatch::IntegrationTest
  include CsrfRequests
  setup do
    @tf = Organization.create!(slug: 'kb-tf', name: 'KB TeamFlow', vertical: 'b2b_saas', currency: 'USD')
    @nm = Organization.create!(slug: 'kb-nm', name: 'KB NovaMart', vertical: 'ecommerce', currency: 'VND')
    @owner_user = User.create!(email: 'kb-owner@example.test')
    @agent_user = User.create!(email: 'kb-agent@example.test')
    @viewer_user = User.create!(email: 'kb-viewer@example.test')
    @other_user = User.create!(email: 'kb-other@example.test')
    @owner = Membership.create!(organization: @tf, user: @owner_user, role: 'owner')
    @agent = Membership.create!(organization: @tf, user: @agent_user, role: 'agent')
    @viewer = Membership.create!(organization: @tf, user: @viewer_user, role: 'viewer')
    @other = Membership.create!(organization: @nm, user: @other_user, role: 'admin')
  end

  test 'draft has no search results even when matching query' do
    create_version(@tf, 'TF-KB-X1', 'draft secret phrase for approved-only filter')
    assert_empty results(@tf, 'agent', 'secret')
    sign_in(@owner)
    get knowledge_articles_path, params: {q: 'secret'}
    assert_response :success
    assert_select 'body', text: /No matching approved content/
  end

  test 'approved version returns attributable chunk for matching tenant and locale only' do
    create_version(@tf, 'TF-KB-X2', 'The Pro quota is 120 requests per minute', approved: true)
    create_version(@nm, 'NM-KB-X2', 'The Pro quota is 120 requests per minute', approved: true)
    hits = results(@tf, 'agent', 'quota')
    assert_equal 1, hits.size
    assert_equal 'TF-KB-X2', hits.first.article_key
    assert_match(/TF-KB-X2@en:v1#chunk-0/, hits.first.citation)
    assert_equal 64, hits.first.sha256.size
    assert_empty KnowledgeRetrieval.search(organization: @tf, role: 'agent', query: 'quota', locale: 'vi')
  end

  test 'agent-only evidence inaccessible to viewer but available to agent' do
    create_version(@tf, 'TF-KB-AGENT', 'Incident sensitive report restricted', approved: true, audience: 'agent')
    assert_empty results(@tf, 'viewer', 'restricted')
    assert_equal 1, results(@tf, 'agent', 'restricted').size
    sign_in(@viewer)
    get knowledge_articles_path
    assert_select 'body', text: /TF-KB-AGENT/, count: 0
  end

  test 'future-dated and expired versions are not returned' do
    create_version(@tf, 'TF-KB-OLD', 'expired coverage details', approved: true, from: Date.new(2025, 1, 1), to: Date.new(2025, 2, 1))
    create_version(@tf, 'TF-KB-FUTURE', 'future coverage details', approved: true, from: Date.new(2099, 1, 1))
    assert_empty results(@tf, 'agent', 'coverage')
  end

  test 'agent cannot publish and owner can approve with audit record' do
    version = create_version(@tf, 'TF-KB-APPROVE', 'Approve this audited policy note')
    sign_in(@agent)
    post_with_csrf approve_knowledge_article_path(version.knowledge_article), params: {version_id: version.id}
    assert_response :forbidden
    assert_equal 'draft', version.reload.status
    sign_in(@owner)
    post_with_csrf approve_knowledge_article_path(version.knowledge_article), params: {version_id: version.id, review_attested: '1', reviewer_notes: 'Policy and language reviewed by authorized owner.'}
    assert_redirected_to knowledge_article_path(version.knowledge_article, locale: 'en')
    assert_equal 'approved', version.reload.status
    assert_equal @owner_user.id, version.approved_by
    assert_equal 'kb.version_approved', AuditEvent.last.action
    assert_equal true, AuditEvent.last.metadata.fetch('editorial_attested')
    assert_equal 'Policy and language reviewed by authorized owner.', AuditEvent.last.metadata.fetch('reviewer_notes')
    assert_equal 1, results(@tf, 'agent', 'audited').length
  end

  test 'owner cannot approve without editorial notes and attestation' do
    version = create_version(@tf, 'TF-KB-NEEDS-REVIEW', 'Draft requires human editorial review')
    sign_in(@owner)
    post_with_csrf approve_knowledge_article_path(version.knowledge_article), params: {version_id: version.id}
    assert_redirected_to knowledge_article_path(version.knowledge_article)
    assert_equal 'draft', version.reload.status
    post_with_csrf approve_knowledge_article_path(version.knowledge_article), params: {
      version_id: version.id, review_attested: '1', reviewer_notes: 'short'
    }
    assert_redirected_to knowledge_article_path(version.knowledge_article)
    assert_equal 'draft', version.reload.status
  end

  test 'owner cannot approve another tenant version' do
    other_version = create_version(@nm, 'NM-KB-PRIVATE', 'another tenant private evidence')
    sign_in(@owner)
    post_with_csrf approve_knowledge_article_path(other_version.knowledge_article), params: {version_id: other_version.id}
    assert_response :not_found
    assert_equal 'draft', other_version.reload.status
  end

  test 'owner can compare both language drafts without publishing' do
    en = create_version(@tf, 'TF-KB-COMPARE', 'English review draft')
    vi_body = 'Bản tiếng Việt để đối chiếu'
    vi = KnowledgeArticleVersion.create!(organization: @tf, knowledge_article: en.knowledge_article,
      locale: 'vi', version_number: 1, title: 'Phiên bản tiếng Việt', body: vi_body,
      sha256: Digest::SHA256.hexdigest(vi_body), policy_version: '1.0.0',
      source_blueprint_sha256: 'test', effective_from: Date.new(2026, 10, 28), status: 'draft')
    KnowledgeChunk.create!(organization: @tf, knowledge_article_version: vi, chunk_index: 0,
      body: vi_body, sha256: Digest::SHA256.hexdigest(vi_body))
    sign_in(@owner)
    get compare_knowledge_article_path(en.knowledge_article)
    assert_response :success
    assert_select '[lang="vi"]', text: /Bản tiếng Việt để đối chiếu/
    assert_select '[lang="en"]', text: /English review draft/
    assert_equal 'draft', en.reload.status
    assert_equal 'draft', vi.reload.status
  end

  test 'agent viewer and other-tenant owner cannot compare drafts' do
    version = create_version(@tf, 'TF-KB-COMPARE-BLOCK', 'Only owner editorial view')
    sign_in(@agent)
    get compare_knowledge_article_path(version.knowledge_article)
    assert_response :forbidden
    sign_in(@viewer)
    get compare_knowledge_article_path(version.knowledge_article)
    assert_response :forbidden
    sign_in(@other)
    get compare_knowledge_article_path(version.knowledge_article)
    assert_response :not_found
  end

  test 'old draft cannot be approved when a newer draft exists' do
    old = create_version(@tf, 'TF-KB-OLD-DRAFT', 'Original candidate')
    body = 'Updated editorial draft v2'
    revised = KnowledgeArticleVersion.create!(organization: @tf, knowledge_article: old.knowledge_article,
      locale: 'en', version_number: 2, title: 'Updated v2', body: body,
      sha256: Digest::SHA256.hexdigest(body), policy_version: '1.0.0',
      source_blueprint_sha256: 'test', effective_from: Date.new(2026, 10, 28), status: 'draft')
    KnowledgeChunk.create!(organization: @tf, knowledge_article_version: revised, chunk_index: 0,
      body: body, sha256: Digest::SHA256.hexdigest(body))
    sign_in(@owner)
    post_with_csrf approve_knowledge_article_path(old.knowledge_article), params: {
      version_id: old.id, review_attested: '1', reviewer_notes: 'Reviewed with reference to approved policy.'
    }
    assert_redirected_to knowledge_article_path(old.knowledge_article)
    assert_equal 'draft', old.reload.status
    assert_equal 'draft', revised.reload.status
  end

  test 'viewer cannot open draft by version id' do
    version = create_version(@tf, 'TF-KB-DRAFT', 'draft-only private article')
    sign_in(@viewer)
    get knowledge_article_path(version.knowledge_article), params: {version_id: version.id}
    assert_response :not_found
  end

  private

  def results(org, role, query)
    KnowledgeRetrieval.search(organization: org, role: role, query: query, locale: 'en')
  end

  def sign_in(membership)
    post_with_csrf demo_sign_in_path, params: {membership_id: membership.id, locale: 'en'}, csrf_page: demo_sign_in_path
    assert_redirected_to root_path
  end

  def create_version(org, key, body, approved: false, audience: 'public', from: Date.new(2026, 10, 28), to: nil)
    article = KnowledgeArticle.create!(organization: org, article_key: key, category: 'test', audience: audience, policy_refs: [])
    reviewer = org == @nm ? @other : @owner
    version = KnowledgeArticleVersion.create!(organization: org, knowledge_article: article,
      locale: 'en', version_number: 1, title: key, body: body, sha256: Digest::SHA256.hexdigest(body),
      policy_version: '1.0.0', source_blueprint_sha256: 'test', effective_from: from, effective_to: to,
      status: approved ? 'approved' : 'draft', approved_by: approved ? reviewer.user_id : nil,
      approved_at: approved ? Time.current : nil)
    KnowledgeChunk.create!(organization: org, knowledge_article_version: version,
      chunk_index: 0, body: body, sha256: Digest::SHA256.hexdigest(body))
    version
  end
end
