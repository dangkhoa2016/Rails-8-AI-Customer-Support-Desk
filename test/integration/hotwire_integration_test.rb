# frozen_string_literal: true
require 'test_helper'
require_relative '../support/csrf_requests'
require 'securerandom'

class HotwireIntegrationTest < ActionDispatch::IntegrationTest
  include CsrfRequests

  setup do
    @team = Organization.create!(slug: 'hw-team', name: 'Hotwire Team', vertical: 'b2b_saas', currency: 'USD')
    @other = Organization.create!(slug: 'hw-other', name: 'Hotwire Other', vertical: 'ecommerce', currency: 'VND')
    @agent = Membership.create!(organization: @team, role: 'agent',
      user: User.create!(email: 'hw-agent@example.test'))
    @viewer = Membership.create!(organization: @team, role: 'viewer',
      user: User.create!(email: 'hw-viewer@example.test'))
    @customer = Customer.create!(organization: @team, external_key: 'HW-C-001',
      synthetic_email: 'hw-c-001@example.test', locale: 'vi')
    @ticket = Ticket.create!(organization: @team, customer: @customer,
      number: 'HW-TICKET-001', category: 'authentication', priority: 'P2', status: 'open')
    @other_customer = Customer.create!(organization: @other, external_key: 'HW-OTHER-001',
      synthetic_email: 'hw-other@example.test', locale: 'en')
    @other_ticket = Ticket.create!(organization: @other, customer: @other_customer,
      number: 'HW-OTHER-TICKET', category: 'order_status', priority: 'P3', status: 'open')
  end

  test 'Hotwire JavaScript and anti-cache privacy settings appear on every authenticated page' do
    sign_in(@agent)
    get root_path
    assert_response :success
    assert_select 'script[type=importmap]', count: 1
    assert_select 'script[type=module]', minimum: 1
    assert_select 'meta[name=turbo-cache-control][content=no-cache]', count: 1
    assert_select 'meta[name=turbo-prefetch][content=false]', count: 1
    assert_select 'nav [aria-current=page]', count: 1
    assert_select 'form[action="/demo/sign_out"][data-turbo=false]', 1
  end

  test 'login and logout forms bypass Turbo to prevent cached cross-tenant sessions' do
    get demo_sign_in_path
    assert_response :success
    assert_select 'form[action="/demo/sign_in"][data-turbo=false]', 1
    sign_in(@agent)
    delete demo_sign_out_path, headers: csrf_headers_from(root_path)
    assert_response :see_other
    get root_path
    assert_redirected_to demo_sign_in_path
  end

  test 'ticket and KB filter frames preserve tenant scope' do
    sign_in(@agent)
    get tickets_path(q: 'HW-TICKET'), headers: {'Turbo-Frame' => 'tickets_listing'}
    assert_response :success
    assert_select 'turbo-frame#tickets_listing[data-turbo-action=advance]', 1
    assert_select 'turbo-frame#tickets_listing', text: /HW-TICKET-001/
    assert_select 'turbo-frame#tickets_listing', text: /HW-OTHER-TICKET/, count: 0
    assert_select 'turbo-frame#tickets_listing a[data-turbo-frame=_top]', minimum: 1
    get knowledge_articles_path(q: 'synthetic'), headers: {'Turbo-Frame' => 'kb_search_results'}
    assert_response :success
    assert_select 'turbo-frame#kb_search_results[data-turbo-action=advance]', 1
  end

  test 'customer search and pagination stay tenant scoped' do
    22.times do |i|
      Customer.create!(organization: @team, external_key: format('HW-EXTRA-%03d', i),
        synthetic_email: "hw-extra-#{i}@example.test", locale: 'vi')
    end
    sign_in(@viewer)
    get customers_path(page: 1), headers: {'Turbo-Frame' => 'customers_listing'}
    assert_response :success
    assert_select 'turbo-frame#customers_listing[data-turbo-action=advance]', 1
    assert_select 'turbo-frame#customers_listing tbody tr', count: 20
    assert_select 'turbo-frame#customers_listing', text: /HW-OTHER-001/, count: 0
    get customers_path(page: 2), headers: {'Turbo-Frame' => 'customers_listing'}
    assert_response :success
    assert_select 'turbo-frame#customers_listing tbody tr', count: 3
    get customers_path(q: 'HW-C-001'), headers: {'Turbo-Frame' => 'customers_listing'}
    assert_response :success
    assert_select 'turbo-frame#customers_listing tbody tr', count: 1
    get customers_path(q: 'HW-OTHER')
    assert_response :success
    assert_select 'turbo-frame#customers_listing tbody tr', count: 0
  end

  test 'status change uses Turbo Stream without bypassing server authorization' do
    sign_in(@agent)
    patch_with_stream(status_ticket_path(@ticket), status: 'resolved')
    assert_response :success
    assert_equal 'text/vnd.turbo-stream.html', response.media_type
    assert_select 'turbo-stream[action=replace][target=ticket_summary]', 1
    assert_select 'turbo-stream[action=replace][target=ticket_status_controls]', 1
    assert_select 'turbo-stream[action=update][target=flash_messages]', 1
    assert_equal 'resolved', @ticket.reload.status
    assert_equal 1, AuditEvent.where(organization_id: @team.id, action: 'ticket.status_changed').count

    patch_with_stream(status_ticket_path(@other_ticket), status: 'resolved')
    assert_response :not_found
    assert_equal 'open', @other_ticket.reload.status
  end

  test 'internal note updates conversation and resets draft using Turbo Streams' do
    sign_in(@agent)
    post_with_stream(ticket_ticket_messages_path(@ticket),
      body: 'Synthetic internal note from Turbo', visibility: 'internal',
      idempotency_key: SecureRandom.uuid)
    assert_response :success
    assert_equal 'text/vnd.turbo-stream.html', response.media_type
    assert_select 'turbo-stream[action=replace][target=ticket_conversation]', 1
    assert_select 'turbo-stream[action=replace][target=ticket_reply_form]', 1
    assert_select 'turbo-stream[action=update][target=flash_messages]', 1
    assert_equal 1, TicketMessage.where(organization_id: @team.id, ticket_id: @ticket.id).count
    assert_equal 1, AuditEvent.where(organization_id: @team.id, action: 'ticket.internal_note_added').count
  end

  test 'public replies still require explicit human attestation in Turbo requests' do
    sign_in(@agent)
    post_with_stream(ticket_ticket_messages_path(@ticket),
      body: 'Unapproved reply must not be written', visibility: 'public',
      idempotency_key: SecureRandom.uuid)
    assert_response :see_other
    assert_equal 0, TicketMessage.where(organization_id: @team.id).count
    assert_equal 0, AuditEvent.where(organization_id: @team.id).count

    post_with_stream(ticket_ticket_messages_path(@ticket),
      body: 'Approved synthetic reply', visibility: 'public',
      idempotency_key: SecureRandom.uuid, review_confirmed: '1')
    assert_response :success
    assert_select 'turbo-stream[action=replace][target=ticket_conversation]', 1
    assert_equal 1, TicketMessage.where(organization_id: @team.id, visibility: 'public').count
    assert_equal 1, AuditEvent.where(organization_id: @team.id, action: 'ticket.public_reply_approved').count
  end

  test 'Viewer cannot mutate ticket even with Turbo stream content negotiation' do
    sign_in(@viewer)
    patch_with_stream(status_ticket_path(@ticket), status: 'resolved')
    assert_response :forbidden
    post_with_stream(ticket_ticket_messages_path(@ticket), body: 'write',
      visibility: 'internal', idempotency_key: SecureRandom.uuid)
    assert_response :forbidden
    assert_equal 'open', @ticket.reload.status
    assert_equal 0, TicketMessage.where(organization_id: @team.id).count
  end

  private

  def sign_in(membership)
    post_with_csrf demo_sign_in_path, params: {membership_id: membership.id, locale: 'en'},
      csrf_page: demo_sign_in_path
    assert_redirected_to root_path
  end

  def patch_with_stream(path, params)
    patch path, params: params,
      headers: csrf_headers_from(root_path).merge('Accept' => 'text/vnd.turbo-stream.html')
  end

  def post_with_stream(path, params)
    post path, params: params,
      headers: csrf_headers_from(root_path).merge('Accept' => 'text/vnd.turbo-stream.html')
  end
end
