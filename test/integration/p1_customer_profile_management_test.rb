# frozen_string_literal: true
require 'test_helper'
require_relative '../support/csrf_requests'

class P1CustomerProfileManagementTest < ActionDispatch::IntegrationTest
  include CsrfRequests

  setup do
    @tf = Organization.create!(slug: 'p1-customer-tf', name: 'P1 TeamFlow', vertical: 'b2b_saas', currency: 'USD')
    @nm = Organization.create!(slug: 'p1-customer-nm', name: 'P1 NovaMart', vertical: 'ecommerce', currency: 'VND')
    @owner = member(@tf, 'owner', 'p1-owner@example.test')
    @admin = member(@tf, 'admin', 'p1-admin@example.test')
    @agent = member(@tf, 'agent', 'p1-agent@example.test')
    @viewer = member(@tf, 'viewer', 'p1-viewer@example.test')
    @other = Customer.create!(organization: @nm, external_key: 'P1-OTHER-C',
      display_name: 'Other tenant', locale: 'vi', synthetic_email: 'other@example.test')
    @customer = Customer.create!(organization: @tf, external_key: 'P1-TF-BASE',
      display_name: 'Original Customer', locale: 'vi',
      synthetic_email: 'original@example.test', company_name: 'Demo Inc')
  end

  test 'owner creates a synthetic customer and cannot set tenant from parameters' do
    login(@owner)
    get new_customer_path
    assert_response :success
    post_with_csrf customers_path, params: {organization_id: @nm.id,
      customer: {external_key: 'P1-TF-NEW', display_name: 'Synthetic New',
        locale: 'en', synthetic_email: 'new@example.test', company_name: 'New Co.'}}
    created = Customer.find_by!(organization: @tf, external_key: 'P1-TF-NEW')
    assert_equal 'New Co.', created.company_name
    assert_redirected_to customer_path(created)
    assert_equal 'customer.created', AuditEvent.last.action
  end

  test 'admin edits profile and cannot modify immutable customer key' do
    login(@admin)
    patch_with_csrf customer_path(@customer), params: {customer: {
      external_key: 'P1-FORGED-KEY', display_name: 'Updated Customer', locale: 'en',
      synthetic_email: 'updated@example.test', company_name: 'Updated Co',
      contact_phone: '000 123 456'}}
    assert_redirected_to customer_path(@customer)
    assert_equal 'P1-TF-BASE', @customer.reload.external_key
    assert_equal 'Updated Co', @customer.company_name
    assert_equal 'en', @customer.locale
    assert_equal 'customer.profile_updated', AuditEvent.last.action
  end

  test 'agents and viewers cannot modify customer profiles' do
    [@agent, @viewer].each do |identity|
      login(identity)
      get new_customer_path
      assert_response :forbidden
      patch_with_csrf customer_path(@customer), params: {customer: {
        display_name: 'Hacked', locale: 'vi', synthetic_email: 'hacked@example.test'}}
      assert_response :forbidden
      patch_with_csrf archive_customer_path(@customer), params: {}
      assert_response :forbidden
    end
    assert_equal 'Original Customer', @customer.reload.display_name
  end

  test 'customer archive preserves ticket history and prevents new tickets' do
    ticket = Ticket.create!(organization: @tf, customer: @customer, number: 'P1-CUST-TICKET',
      category: 'authentication', priority: 'P3', status: 'new')
    login(@owner)
    patch_with_csrf archive_customer_path(@customer), params: {}
    assert_redirected_to customers_path
    assert @customer.reload.archived?
    assert Ticket.exists?(ticket.id)
    get customers_path
    assert_select 'body', text: /P1-TF-BASE/, count: 0
    get customers_path(include_archived: '1')
    assert_select 'body', text: /P1-TF-BASE/
    post_with_csrf tickets_path, params: {customer_id: @customer.id,
      category: 'authentication', priority: 'P3', initial_message: 'A synthetic new issue'}
    assert_response :not_found
    assert_equal 1, Ticket.where(customer_id: @customer.id).count
    assert_equal 'customer.archived', AuditEvent.last.action
  end

  test 'forged cross-tenant updates are not found and viewer cannot see contact details' do
    login(@owner)
    patch_with_csrf customer_path(@other), params: {customer: {
      display_name: 'Hacked', locale: 'en', synthetic_email: 'hacked@example.test'}}
    assert_response :not_found
    assert_equal 'Other tenant', @other.reload.display_name
    login(@viewer)
    get customer_path(@customer)
    assert_response :success
    assert_select 'body', text: /original@example.test/, count: 0
  end

  test 'invalid real email and duplicate key are rejected' do
    login(@owner)
    post_with_csrf customers_path, params: {customer: {
      external_key: 'P1-REAL-EMAIL', display_name: 'Real Address', locale: 'vi',
      synthetic_email: 'someone@gmail.com'}}
    assert_redirected_to new_customer_path
    assert_nil Customer.find_by(external_key: 'P1-REAL-EMAIL')
    post_with_csrf customers_path, params: {customer: {
      external_key: @customer.external_key, display_name: 'Duplicate', locale: 'vi',
      synthetic_email: 'duplicate@example.test'}}
    assert_redirected_to new_customer_path
    assert_equal 1, Customer.where(organization: @tf, external_key: @customer.external_key).count
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
