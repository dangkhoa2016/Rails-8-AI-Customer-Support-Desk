# frozen_string_literal: true
require 'test_helper'
require_relative '../support/csrf_requests'

class P0IdentityRbacSecurityTest < ActionDispatch::IntegrationTest
  include CsrfRequests
  PASS = 'A-very-strong-passphrase-2026!'

  setup do
    @tf = Organization.create!(slug: 'rbac-teamflow', name: 'RBAC TeamFlow', vertical: 'b2b_saas', currency: 'USD')
    @nm = Organization.create!(slug: 'rbac-novamart', name: 'RBAC NovaMart', vertical: 'ecommerce', currency: 'VND')
    @viewer_user = User.create!(email: 'p0-viewer@example.test', password: PASS)
    @viewer = Membership.create!(organization: @tf, user: @viewer_user, role: 'viewer')
    @owner_user = User.create!(email: 'p0-owner@example.test', password: PASS)
    @owner = Membership.create!(organization: @tf, user: @owner_user, role: 'owner')
    @agent = Membership.create!(organization: @tf,
      user: User.create!(email: 'p0-agent@example.test'), role: 'agent')
    @admin = Membership.create!(organization: @tf,
      user: User.create!(email: 'p0-admin@example.test'), role: 'admin')
    @customer = Customer.create!(organization: @tf, external_key: 'P0-TF-C',
      locale: 'en', synthetic_email: 'p0-tf-c@example.test')
    @ticket = Ticket.create!(organization: @tf, customer: @customer,
      number: 'P0-TF-TICKET-1', category: 'authentication', priority: 'P3')
    TicketMessage.create!(organization: @tf, ticket: @ticket,
      actor_type: 'customer', visibility: 'public', body: 'PUBLIC-SYNTHETIC-TICKET-TEXT')
    TicketMessage.create!(organization: @tf, ticket: @ticket,
      actor_type: 'agent', actor_user_id: @owner_user.id, visibility: 'internal',
      body: 'PRIVATE-INTERNAL-TICKET-DETAIL-NEVER-FOR-VIEWER')
  end

  test 'viewer cannot read internal ticket note or its content' do
    demo_login(@viewer)
    get ticket_path(@ticket)
    assert_response :success
    assert_select 'body', text: /PUBLIC-SYNTHETIC-TICKET-TEXT/
    assert_select 'body', text: /PRIVATE-INTERNAL-TICKET-DETAIL-NEVER-FOR-VIEWER/, count: 0
    assert_select '#ticket_reply_form', count: 0
  end

  test 'tenant agents and admins see internal notes with correct role permissions' do
    [@agent, @admin, @owner].each do |member|
      demo_login(member)
      get ticket_path(@ticket)
      assert_response :success
      assert_select 'body', text: /PRIVATE-INTERNAL-TICKET-DETAIL-NEVER-FOR-VIEWER/
    end
    assert SupportDeskAccessPolicy.new(@owner).may_manage_membership?(
      target_role: 'admin', new_role: 'agent')
    refute SupportDeskAccessPolicy.new(@admin).may_manage_membership?(
      target_role: 'owner', new_role: 'agent')
    refute SupportDeskAccessPolicy.new(@agent).allowed?(:staff_manage)
  end

  test 'deactivation of membership or user revokes an existing demo session immediately' do
    demo_login(@owner)
    get ticket_path(@ticket)
    assert_response :success
    @owner.update!(active: false)
    get ticket_path(@ticket)
    assert_redirected_to demo_sign_in_path
    @owner.update!(active: true)
    demo_login(@owner)
    @owner_user.update!(active: false)
    get ticket_path(@ticket)
    assert_redirected_to demo_sign_in_path
  end

  test 'password login is forbidden unless separately enabled' do
    get password_sign_in_path
    assert_response :forbidden
    post password_sign_in_path,
      params: {email: @owner_user.email, password: PASS, organization_slug: @tf.slug}
    # CSRF may reject the disabled endpoint before its authorization gate.
    assert_includes [403, 422], response.status
  end

  test 'password login cannot access a tenant without active membership' do
    password_mode do
      get password_sign_in_path
      assert_response :success
      post_with_csrf password_sign_in_path, csrf_page: password_sign_in_path,
        params: {email: @owner_user.email, password: PASS, organization_slug: @nm.slug}
      assert_response :unauthorized
      get root_path
      assert_redirected_to password_sign_in_path
      post_with_csrf password_sign_in_path, csrf_page: password_sign_in_path,
        params: {email: @owner_user.email, password: 'incorrect-password-2026', organization_slug: @tf.slug}
      assert_response :unauthorized
    end
  end

  test 'verified user authenticates to own tenant, then role is rechecked on each request' do
    password_mode do
      post_with_csrf password_sign_in_path, csrf_page: password_sign_in_path,
        params: {email: @owner_user.email, password: PASS, organization_slug: @tf.slug}
      assert_redirected_to root_path
      get ticket_path(@ticket)
      assert_response :success
      @owner.update!(active: false)
      get ticket_path(@ticket)
      assert_redirected_to password_sign_in_path
      post_with_csrf demo_sign_in_path, csrf_page: password_sign_in_path,
        params: {membership_id: @owner.id}
      assert_response :forbidden
    end
  end

  test 'separate platform administrator cannot impersonate a tenant' do
    platform = PlatformAdmin.create!(email: 'p0-platform@example.test',
      display_name: 'Platform Operator', password: PASS)
    password_mode do
      platform_mode do
        post_with_csrf password_sign_in_path, csrf_page: password_sign_in_path,
          params: {email: platform.email, password: PASS, organization_slug: ''}
        assert_response :unauthorized
        post_with_csrf platform_sign_in_path, csrf_page: platform_sign_in_path,
          params: {email: platform.email, password: PASS}
        assert_redirected_to platform_dashboard_path
        get platform_dashboard_path
        assert_response :success
        assert_select 'body', text: /Platform overview|Tổng quan quản trị nền tảng/
        assert_select 'body', text: /PRIVATE-INTERNAL-TICKET-DETAIL/, count: 0
        get ticket_path(@ticket)
        assert_redirected_to password_sign_in_path
      end
    end
  end

  test 'password-only mode cannot accidentally inherit demo session login' do
    demo_login(@owner)
    password_mode do
      get root_path
      assert_redirected_to password_sign_in_path
    end
  end

  private

  def demo_login(membership)
    post_with_csrf demo_sign_in_path, csrf_page: demo_sign_in_path,
      params: {membership_id: membership.id, locale: 'en'}
    assert_redirected_to root_path
  end

  def platform_mode
    prior = ENV['P0_PLATFORM_AUTH_TEST_MODE']
    ENV['P0_PLATFORM_AUTH_TEST_MODE'] = 'YES'
    yield
  ensure
    prior ? ENV['P0_PLATFORM_AUTH_TEST_MODE'] = prior : ENV.delete('P0_PLATFORM_AUTH_TEST_MODE')
  end

  def password_mode
    before = ENV['P0_PASSWORD_AUTH_TEST_MODE']
    ENV['P0_PASSWORD_AUTH_TEST_MODE'] = 'YES'
    yield
  ensure
    before ? ENV['P0_PASSWORD_AUTH_TEST_MODE'] = before : ENV.delete('P0_PASSWORD_AUTH_TEST_MODE')
  end
end
