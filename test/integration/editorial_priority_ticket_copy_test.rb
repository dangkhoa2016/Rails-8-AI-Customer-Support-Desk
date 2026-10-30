# frozen_string_literal: true
require 'test_helper'
require_relative '../support/csrf_requests'
require 'digest'

# Read-only UI regression for tenant-scoped priority KB counts and demo ticket copy.
class EditorialPriorityTicketCopyTest < ActionDispatch::IntegrationTest
  include CsrfRequests

  setup do
    @tf = Organization.create!(slug: 'teamflow-cloud', name: 'TeamFlow Cloud',
      vertical: 'b2b_saas', currency: 'USD')
    @nm = Organization.create!(slug: 'novamart-store', name: 'NovaMart Store',
      vertical: 'ecommerce', currency: 'VND')
    @tf_user = User.create!(email: 'editor-priority-tf@example.test')
    @nm_user = User.create!(email: 'editor-priority-nm@example.test')
    @tf_owner = Membership.create!(organization: @tf, user: @tf_user, role: 'owner')
    @nm_owner = Membership.create!(organization: @nm, user: @nm_user, role: 'owner')
    @tf_agent = Membership.create!(organization: @tf,
      user: User.create!(email: 'editor-priority-agent@example.test'), role: 'agent')

    %w[TF-KB-012 TF-KB-015].each do |key|
      create_bilingual_article(@tf, key, @tf_user, pending_en: key == 'TF-KB-015')
    end
    %w[NM-KB-014 NM-KB-020 NM-KB-029 NM-KB-030].each do |key|
      create_bilingual_article(@nm, key, @nm_user)
    end
    customer = Customer.create!(organization: @tf, external_key: 'EDITOR-TF-001',
      locale: 'vi', synthetic_email: 'editor-customer@example.test')
    @ticket = Ticket.create!(organization: @tf, customer: customer,
      number: 'TF-EDITOR-TICKET-001', category: 'billing_subscription',
      status: 'pending_internal', priority: 'P2')
  end

  test 'TeamFlow owner sees exactly two priority articles and real VI/EN statuses' do
    sign_in(@tf_owner, 'vi')
    get knowledge_articles_path
    assert_response :success
    assert_select 'h2', text: 'Bài KB ưu tiên — TeamFlow Cloud (2 bài)', count: 1
    assert_select '.priority-language-status', count: 2
    assert_select '.priority-language-status', text: /VI: Đã duyệt.*EN: Chờ duyệt/m, count: 1
    assert_select 'a', text: 'Xem đối chiếu VI / EN', minimum: 2
    assert_select 'body', text: /NM-KB-014|NM-KB-020|NM-KB-029|NM-KB-030/, count: 0
    assert_select 'body', text: /6 bài ưu tiên cần rà soát|Modal NOT_RUN/, count: 0
  end

  test 'NovaMart owner sees four article IDs, not the TeamFlow IDs' do
    sign_in(@nm_owner, 'vi')
    get knowledge_articles_path
    assert_response :success
    assert_select 'h2', text: 'Bài KB ưu tiên — NovaMart Store (4 bài)', count: 1
    assert_select '.priority-language-status', count: 4
    assert_select '.priority-language-status span', text: /Đã duyệt/, count: 8
    assert_select 'body', text: /TF-KB-012|TF-KB-015/, count: 0
  end

  test 'English heading translates and non-reviewing agent cannot access editorial priorities' do
    sign_in(@tf_owner, 'en')
    get knowledge_articles_path
    assert_response :success
    assert_select 'h2', text: 'Priority KB articles — TeamFlow Cloud (2)', count: 1

    sign_in(@tf_agent, 'vi')
    get knowledge_articles_path
    assert_response :success
    assert_select 'h2', text: /Bài KB ưu tiên/, count: 0
    assert_select '.priority-language-status', count: 0
  end

  test 'ticket form clearly distinguishes internal note from public saved reply with no external delivery' do
    sign_in(@tf_owner, 'vi')
    get ticket_path(@ticket)
    assert_response :success
    assert_select '#ticket_reply_form h2', text: 'Ghi chú và phản hồi (demo)'
    assert_select '#visibility option[value=internal]', text: /chỉ nhân viên xem/
    assert_select '#visibility option[value=public]', text: /chỉ lưu trong demo/
    assert_select '#ticket_reply_form', text: /không có email\/tin nhắn\/notification gửi ra bên ngoài/
    assert_select '#ticket_reply_form', text: /Chỉ.*phản hồi công khai/i
    assert_select 'input[name=review_confirmed]', count: 1
    assert_select 'input[name=idempotency_key]', count: 1
  end

  private

  def sign_in(membership, locale)
    post_with_csrf demo_sign_in_path, csrf_page: demo_sign_in_path,
      params: {membership_id: membership.id, locale: locale}
    assert_redirected_to root_path
  end

  def create_bilingual_article(org, key, user, pending_en: false)
    article = KnowledgeArticle.create!(organization: org, article_key: key,
      category: 'billing_subscription', audience: 'public', policy_refs: [])
    %w[vi en].each do |locale|
      body = "Synthetic #{key} #{locale} approved policy excerpt"
      approved = !(pending_en && locale == 'en')
      KnowledgeArticleVersion.create!(organization: org, knowledge_article: article,
        locale: locale, title: "#{key} #{locale}", body: body,
        sha256: Digest::SHA256.hexdigest(body),
        version_number: 2, policy_version: org.policy_version,
        source_blueprint_sha256: 'm53-editorial-ui-synthetic',
        effective_from: Date.yesterday, status: approved ? 'approved' : 'draft',
        approved_by: approved ? user.id : nil,
        approved_at: approved ? Time.current : nil)
    end
  end
end
