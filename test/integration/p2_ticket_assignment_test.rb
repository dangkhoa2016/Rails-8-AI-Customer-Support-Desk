# frozen_string_literal: true
require 'test_helper'
require_relative '../support/csrf_requests'

class P2TicketAssignmentTest < ActionDispatch::IntegrationTest
  include CsrfRequests

  setup do
    @tf = Organization.create!(slug: 'p2-ticket-teamflow', name: 'P2 TF', vertical: 'b2b_saas', currency: 'USD')
    @nm = Organization.create!(slug: 'p2-ticket-novamart', name: 'P2 NM', vertical: 'ecommerce', currency: 'VND')
    @owner = member(@tf, 'owner', 'p2-owner@example.test')
    @admin = member(@tf, 'admin', 'p2-admin@example.test')
    @agent = member(@tf, 'agent', 'p2-agent@example.test')
    @viewer = member(@tf, 'viewer', 'p2-viewer@example.test')
    @other = member(@nm, 'agent', 'p2-other@example.test')
    @customer = Customer.create!(organization: @tf, external_key: 'P2-CUST',
      locale: 'vi', synthetic_email: 'p2-cust@example.test')
    @ticket = Ticket.create!(organization: @tf, customer: @customer, number: 'P2-TICKET-001',
      category: 'authentication', priority: 'P3', assignee_id: @agent.user_id)
  end

  test 'owner can reassign to another active tenant member, then unassign with audit' do
    login(@owner)
    get ticket_path(@ticket)
    assert_response :success
    assert_select 'form[action=?]', assign_ticket_path(@ticket), count: 1
    patch_with_csrf assign_ticket_path(@ticket), params: {assignee_user_id: @admin.user_id}
    assert_redirected_to ticket_path(@ticket)
    assert_equal @admin.user_id, @ticket.reload.assignee_id
    assert_equal 'ticket.assignee_changed', AuditEvent.last.action
    old_count = AuditEvent.count
    patch_with_csrf assign_ticket_path(@ticket), params: {assignee_user_id: @admin.user_id}
    assert_equal old_count, AuditEvent.count
    patch_with_csrf assign_ticket_path(@ticket), params: {assignee_user_id: ''}
    assert_nil @ticket.reload.assignee_id
  end

  test 'agent and viewer cannot change assignee' do
    [@agent, @viewer].each do |identity|
      login(identity)
      get ticket_path(@ticket)
      assert_response :success
      assert_select 'form[action=?]', assign_ticket_path(@ticket), count: 0
      patch_with_csrf assign_ticket_path(@ticket), params: {assignee_user_id: @owner.user_id}
      assert_response :forbidden
      assert_equal @agent.user_id, @ticket.reload.assignee_id
    end
  end

  test 'cross-tenant assignee, viewer and inactive membership are rejected' do
    login(@admin)
    [@other.user_id, @viewer.user_id, 999_999_999].each do |target|
      patch_with_csrf assign_ticket_path(@ticket), params: {assignee_user_id: target}
      assert_response :unprocessable_entity
      assert_equal @agent.user_id, @ticket.reload.assignee_id
    end
    @agent.update!(active: false)
    patch_with_csrf assign_ticket_path(@ticket), params: {assignee_user_id: @agent.user_id}
    assert_response :unprocessable_entity
    patch_with_csrf assign_ticket_path(@ticket), params: {assignee_user_id: 'not-numeric'}
    assert_response :unprocessable_entity
  end

  test 'tenant filtered listing supports assigned to me, unassigned and denies forged assignee' do
    Ticket.create!(organization: @tf, customer: @customer, number: 'P2-UNASSIGNED',
      category: 'authentication', status: 'new', priority: 'P3')
    login(@agent)
    get tickets_path(assignee_user_id: 'me')
    assert_response :success
    assert_select 'body', text: /P2-TICKET-001/
    assert_select 'body', text: /P2-UNASSIGNED/, count: 0
    get tickets_path(assignee_user_id: 'unassigned')
    assert_select 'body', text: /P2-UNASSIGNED/
    assert_select 'body', text: /P2-TICKET-001/, count: 0
    get tickets_path(assignee_user_id: @other.user_id.to_s)
    assert_select 'body', text: /P2-TICKET-001|P2-UNASSIGNED/, count: 0
  end

  test 'other tenant ticket cannot be assigned by URL manipulation' do
    other_customer = Customer.create!(organization: @nm, external_key: 'P2-NM-C',
      locale: 'vi', synthetic_email: 'p2-nm@example.test')
    other_ticket = Ticket.create!(organization: @nm, customer: other_customer,
      number: 'P2-NM-TICKET', category: 'order_status', priority: 'P3',
      assignee_id: @other.user_id)
    login(@owner)
    patch_with_csrf assign_ticket_path(other_ticket), params: {assignee_user_id: @owner.user_id}
    assert_response :not_found
    assert_equal @other.user_id, other_ticket.reload.assignee_id
  end

  private

  def member(org, role, email)
    user = User.create!(email: email, display_name: role)
    Membership.create!(organization: org, user: user, role: role)
  end

  def login(identity)
    post_with_csrf demo_sign_in_path, csrf_page: demo_sign_in_path,
      params: {membership_id: identity.id, locale: 'en'}
    assert_redirected_to root_path
  end
end
