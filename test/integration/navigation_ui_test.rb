# frozen_string_literal: true
require 'test_helper'
require_relative '../support/csrf_requests'
require 'digest'

class NavigationUiTest < ActionDispatch::IntegrationTest
  include CsrfRequests

  setup do
    @org = Organization.create!(
      slug: 'navigation-demo', name: 'Navigation Demo',
      vertical: 'b2b_saas', currency: 'USD'
    )
    @owner = Membership.create!(
      organization: @org, role: 'owner',
      user: User.create!(email: 'nav-owner@example.test')
    )
    @viewer = Membership.create!(
      organization: @org, role: 'viewer',
      user: User.create!(email: 'nav-viewer@example.test')
    )
    @customer = Customer.create!(
      organization: @org, external_key: 'NAV-C-001',
      synthetic_email: 'nav-c-001@example.test', locale: 'vi'
    )
    @ticket = Ticket.create!(
      organization: @org, customer: @customer, number: 'NAV-TICKET-001',
      category: 'authentication', status: 'open', priority: 'P3'
    )
    @article = KnowledgeArticle.create!(
      organization: @org, article_key: 'NAV-KB-001',
      category: 'demo', audience: 'public', policy_refs: []
    )
    body = 'Synthetic navigation-only KB draft'
    KnowledgeArticleVersion.create!(
      organization: @org, knowledge_article: @article,
      locale: 'en', version_number: 1, title: 'Navigation draft',
      body: body, sha256: Digest::SHA256.hexdigest(body),
      policy_version: '1.0.0', source_blueprint_sha256: 'test',
      effective_from: Date.new(2026, 10, 28), status: 'draft'
    )
  end

  test 'navigation highlights exactly one main section on parent and nested pages' do
    sign_in(@owner)
    {
      root_path => '/',
      tickets_path => '/tickets',
      new_ticket_path => '/tickets',
      ticket_path(@ticket) => '/tickets',
      customers_path => '/customers',
      customer_path(@customer) => '/customers',
      knowledge_articles_path => '/knowledge_articles',
      knowledge_article_path(@article) => '/knowledge_articles',
      compare_knowledge_article_path(@article) => '/knowledge_articles',
      kb_ai_search_path => '/kb/ai-search'
    }.each do |path, active_href|
      get path
      assert_response :success, "#{path} should render"
      assert_active_section(active_href, path)
    end
  end

  test 'active styling remains correct for English, Vietnamese and query filters' do
    sign_in(@owner)
    get tickets_path(locale: 'vi', status: 'open')
    assert_response :success
    assert_select 'html[lang=vi]'
    assert_active_section('/tickets', 'Vietnamese filtered tickets')

    get knowledge_articles_path(locale: 'en')
    assert_response :success
    assert_select 'html[lang=en]'
    assert_active_section('/knowledge_articles', 'English knowledge base')
  end

  test 'viewer sees active public KB and never receives staff AI nav' do
    sign_in(@viewer)
    get knowledge_articles_path
    assert_response :success
    assert_active_section('/knowledge_articles', 'viewer KB', expected_links: 4)
    assert_select 'nav a[href="/kb/ai-search"]', count: 0
    get ticket_path(@ticket)
    assert_response :success
    assert_active_section('/tickets', 'viewer ticket detail', expected_links: 4)
  end

  test 'button and submit cursor styles appear with disabled safeguards' do
    sign_in(@owner)
    get new_ticket_path
    assert_response :success
    assert_select 'input[type=submit]', minimum: 1
    css = response.body[/<style>(.*?)<\/style>/m, 1]
    assert css
    assert_includes css, 'input[type=submit],input[type=button],input[type=reset]'
    assert_includes css, 'cursor:pointer'
    assert_includes css, 'input[type=submit]:disabled'
    assert_includes css, 'cursor:not-allowed'
    assert_includes css, '.navlinks .nav-menu-link.is-active'
    assert_includes css, '.navlinks .nav-menu-link:focus-visible'
  end

  test 'account selection page has no false active main navigation' do
    get demo_sign_in_path
    assert_response :success
    assert_select 'nav .nav-menu-link', count: 0
    assert_select 'nav [aria-current=page]', count: 0
  end

  test 'read-only business-record controller belongs to customers nav section' do
    assert_equal :customers, ApplicationHelper::NAV_SECTIONS.fetch('business_records')
    assert_equal :tickets, ApplicationHelper::NAV_SECTIONS.fetch('ticket_messages')
  end

  private

  def sign_in(membership)
    post_with_csrf demo_sign_in_path,
      params: { membership_id: membership.id, locale: 'en' },
      csrf_page: demo_sign_in_path
    assert_redirected_to root_path
  end

  def assert_active_section(active_href, path, expected_links: 5)
    assert_select 'nav a.nav-menu-link', count: expected_links, message: path
    assert_select 'nav a.nav-menu-link.is-active', count: 1, message: path
    assert_select 'nav a.nav-menu-link[aria-current=page]', count: 1, message: path
    assert_select "nav a.nav-menu-link.is-active[aria-current=page][href='#{active_href}']", count: 1,
      message: "#{path} must activate #{active_href}"
    assert_select 'nav a.nav-menu-link:not(.is-active)[aria-current]', count: 0
  end
end
