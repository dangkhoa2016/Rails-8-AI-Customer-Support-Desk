# frozen_string_literal: true
require 'test_helper'
require_relative '../support/csrf_requests'
require 'securerandom'

class SupportDeskSecurityTest < ActionDispatch::IntegrationTest
  include CsrfRequests
  setup do
    @tf = Organization.create!(slug: 'test-tf', name: 'Test TeamFlow', vertical: 'b2b_saas', currency: 'USD')
    @nm = Organization.create!(slug: 'test-nm', name: 'Test NovaMart', vertical: 'ecommerce', currency: 'VND')
    @agent = User.create!(email: 'agent1@example.test')
    @viewer = User.create!(email: 'viewer1@example.test')
    @other = User.create!(email: 'agent2@example.test')
    @agent_membership = Membership.create!(organization: @tf, user: @agent, role: 'agent')
    @viewer_membership = Membership.create!(organization: @tf, user: @viewer, role: 'viewer')
    @other_membership = Membership.create!(organization: @nm, user: @other, role: 'agent')
    @tf_customer = Customer.create!(organization: @tf, external_key: 'TF-C-TEST', synthetic_email: 'tf-c@example.test', locale: 'vi')
    @nm_customer = Customer.create!(organization: @nm, external_key: 'NM-C-TEST', synthetic_email: 'nm-c@example.test', locale: 'vi')
  end

  test 'unauthenticated dashboard redirects to demo login' do
    get root_path
    assert_redirected_to demo_sign_in_path
  end

  test 'agent can list only own tenant customers and cannot inspect cross tenant customer' do
    sign_in(@agent_membership)
    get customers_path
    assert_response :success
    assert_select 'body', text: /TF-C-TEST/
    assert_select 'body', text: /NM-C-TEST/, count: 0
    get customer_path(@nm_customer)
    assert_response :not_found
  end

  test 'viewer cannot create tickets' do
    sign_in(@viewer_membership)
    post_with_csrf tickets_path, params: ticket_params(@tf_customer)
    assert_response :forbidden
    assert_equal 0, Ticket.count
  end

  test 'agent cannot forge customer from other tenant' do
    sign_in(@agent_membership)
    post_with_csrf tickets_path, params: ticket_params(@nm_customer)
    assert_response :not_found
    assert_equal 0, Ticket.count
  end

  test 'ticket creation is tenant scoped with audit' do
    sign_in(@agent_membership)
    post_with_csrf tickets_path, params: ticket_params(@tf_customer).merge(organization_id: @nm.id)
    ticket = Ticket.sole
    assert_equal @tf.id, ticket.organization_id
    assert_equal @tf_customer.id, ticket.customer_id
    assert_redirected_to ticket_path(ticket)
    assert_equal 'customer', TicketMessage.sole.actor_type
    assert_equal 'ticket.created', AuditEvent.sole.action
  end

  test 'other tenant ticket cannot be seen or updated' do
    ticket = create_ticket(@nm, @nm_customer, 'NM-TICKET-000777')
    sign_in(@agent_membership)
    get ticket_path(ticket)
    assert_response :not_found
    patch_with_csrf status_ticket_path(ticket), params: { status: 'resolved' }
    assert_response :not_found
    assert_equal 'new', ticket.reload.status
  end

  test 'public reply requires explicit agent approval' do
    ticket = create_ticket(@tf, @tf_customer, 'TF-TICKET-000777')
    sign_in(@agent_membership)
    post_with_csrf ticket_ticket_messages_path(ticket), params: reply_params('public', 'a')
    assert_redirected_to ticket_path(ticket)
    assert_equal 0, TicketMessage.count
    assert_equal 0, AuditEvent.count
  end

  test 'approved reply is audited and identical request is idempotent' do
    ticket = create_ticket(@tf, @tf_customer, 'TF-TICKET-000777')
    sign_in(@agent_membership)
    key = SecureRandom.uuid
    2.times do
      post_with_csrf ticket_ticket_messages_path(ticket), params: reply_params('public', 'a', key: key).merge(review_confirmed: '1')
      assert_redirected_to ticket_path(ticket)
    end
    assert_equal 1, TicketMessage.count
    assert_equal 1, AuditEvent.count
    assert_equal 'ticket.public_reply_approved', AuditEvent.sole.action
  end

  test 'viewer cannot use read only business lookup endpoint reserved for agent roles' do
    sign_in(@viewer_membership)
    get teamflow_invoice_path, params: {customer_key: 'TF-C-TEST', invoice_number: 'A-001'}
    assert_response :forbidden
  end

  test 'demo account switching clears first organization session' do
    sign_in(@agent_membership)
    get root_path
    assert_select 'body', text: /Test TeamFlow/
    sign_in(@other_membership)
    get root_path
    assert_select 'body', text: /Test NovaMart/
    assert_select 'body', text: /Test TeamFlow/, count: 0
  end

  private

  def sign_in(membership)
    post_with_csrf demo_sign_in_path, params: {membership_id: membership.id, locale: 'en'}, csrf_page: demo_sign_in_path
    assert_redirected_to root_path
  end

  def ticket_params(customer)
    {customer_id: customer.id, category: 'authentication', priority: 'P3', initial_message: 'Please help me sign in.'}
  end

  def reply_params(visibility, body, key: SecureRandom.uuid)
    {visibility: visibility, body: body, idempotency_key: key}
  end

  def create_ticket(org, customer, number)
    Ticket.create!(organization: org, customer: customer, number: number,
      category: 'authentication', priority: 'P3', status: 'new')
  end
end
