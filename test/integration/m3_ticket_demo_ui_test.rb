# frozen_string_literal: true
require 'test_helper'
require_relative '../support/csrf_requests'

class M3TicketDemoUiTest < ActionDispatch::IntegrationTest
  include CsrfRequests

  setup do
    @tf = Organization.create!(slug: 'm3-test-tf', name: 'M3 Test TF', vertical: 'b2b_saas', currency: 'USD')
    @nm = Organization.create!(slug: 'm3-test-nm', name: 'M3 Test NM', vertical: 'ecommerce', currency: 'VND')
    @agent = User.create!(email: 'm3-tf-agent@example.test')
    @viewer = User.create!(email: 'm3-tf-viewer@example.test')
    @tf_agent = Membership.create!(organization: @tf, user: @agent, role: 'agent')
    @tf_viewer = Membership.create!(organization: @tf, user: @viewer, role: 'viewer')
    @tf_vi = Customer.create!(organization: @tf, external_key: 'M3-TF-VI',
                               synthetic_email: 'm3-vi@example.test', locale: 'vi')
    @tf_en = Customer.create!(organization: @tf, external_key: 'M3-TF-EN',
                               synthetic_email: 'm3-en@example.test', locale: 'en')
    @nm_customer = Customer.create!(organization: @nm, external_key: 'M3-NM-VI',
                                    synthetic_email: 'm3-nm@example.test', locale: 'vi')
    @tf_ticket_vi = Ticket.create!(organization: @tf, customer: @tf_vi, number: 'TF-M3-TEST-VI',
                                   category: 'billing_subscription', status: 'open', priority: 'P2',
                                   business_ref: 'TF-INV-TEST-01')
    @tf_ticket_en = Ticket.create!(organization: @tf, customer: @tf_en, number: 'TF-M3-TEST-EN',
                                   category: 'exports_jobs', status: 'pending_internal', priority: 'P3',
                                   business_ref: 'TF-EXPORT-TEST-01')
    @nm_ticket = Ticket.create!(organization: @nm, customer: @nm_customer, number: 'NM-M3-TEST',
                                category: 'order_status', status: 'open', priority: 'P3',
                                business_ref: 'NM-2026-TEST')
  end

  test 'index remains tenant scoped with status locale and category filters' do
    sign_in(@tf_agent)
    get tickets_path(status: 'open', customer_locale: 'vi', category: 'billing_subscription')
    assert_response :success
    assert_select 'body', text: /TF-M3-TEST-VI/
    assert_select 'body', text: /TF-M3-TEST-EN/, count: 0
    assert_select 'body', text: /NM-M3-TEST/, count: 0
  end

  test 'business reference search stays tenant scoped' do
    sign_in(@tf_agent)
    get tickets_path(q: 'TF-EXPORT-TEST-01')
    assert_response :success
    assert_select 'body', text: /TF-M3-TEST-EN/
    assert_select 'body', text: /TF-M3-TEST-VI/, count: 0
    get tickets_path(q: 'NM-2026-TEST')
    assert_response :success
    assert_select 'body', text: /NM-M3-TEST/, count: 0
  end

  test 'unknown category does not enable another tenants taxonomy' do
    sign_in(@tf_agent)
    get tickets_path(category: 'order_status')
    assert_response :success
    assert_select 'body', text: /TF-M3-TEST-VI/
    assert_select 'body', text: /NM-M3-TEST/, count: 0
  end

  test 'ticket detail never exposes cross-tenant tickets' do
    sign_in(@tf_agent)
    get ticket_path(@nm_ticket)
    assert_response :not_found
  end

  test 'agent sees manual KB search and synthetic explanation' do
    sign_in(@tf_agent)
    get ticket_path(@tf_ticket_vi)
    assert_response :success
    # Navigation and the contextual case panel both offer manual KB search.
    assert_select 'a[href=?]', kb_ai_search_path, count: 2
    assert_select 'body', text: /synthetic|giả lập/i
  end

  test 'viewer cannot launch staff-only AI and cannot change ticket' do
    sign_in(@tf_viewer)
    get ticket_path(@tf_ticket_vi)
    assert_response :success
    assert_select 'a[href=?]', kb_ai_search_path, count: 0
    patch_with_csrf status_ticket_path(@tf_ticket_vi), params: {status: 'resolved'}
    assert_response :forbidden
    assert_equal 'open', @tf_ticket_vi.reload.status
  end

  private

  def sign_in(membership)
    post_with_csrf demo_sign_in_path, params: {membership_id: membership.id, locale: 'vi'}, csrf_page: demo_sign_in_path
    assert_redirected_to root_path
  end
end
