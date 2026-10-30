# frozen_string_literal: true
require 'test_helper'
require_relative '../support/csrf_requests'

class PlatformAdminSeparationTest < ActionDispatch::IntegrationTest
  include CsrfRequests
  PASS = 'strong-unique-platform-password-2026!'

  setup do
    @tenant = Organization.create!(slug: 'p01-separation-org', name: 'Isolated Tenant',
      vertical: 'b2b_saas', currency: 'USD')
    @owner_user = User.create!(email: 'p01-owner@example.test',
      display_name: 'Tenant Owner', password: PASS)
    @owner = Membership.create!(organization: @tenant, user: @owner_user, role: 'owner')
    @platform = PlatformAdmin.create!(email: 'platform-operator@example.test',
      display_name: 'Platform Operator', password: PASS)
  end

  test 'platform credentials have a separate database table without memberships or users flag' do
    assert PlatformAdmin.table_exists?
    refute User.column_names.include?('system_admin')
    assert_equal 1, PlatformAdmin.count
    refute User.exists?(email: @platform.email)
    assert_nil @platform.try(:memberships)
    assert_equal 1, Membership.where(organization_id: @tenant.id).count
    assert_equal %w[admin agent owner viewer], SupportDeskAccessPolicy::ROLE_PERMISSIONS.keys.sort
  end

  test 'platform sign in and dashboard are opt in and disabled by default' do
    get platform_sign_in_path
    assert_response :forbidden
    get platform_dashboard_path
    assert_response :forbidden
    post platform_sign_in_path, params: {email: @platform.email, password: PASS}
    assert_includes [403, 422], response.status
  end

  test 'platform login is a separate identity and displays its own layout and session' do
    platform_mode do
      get platform_sign_in_path
      assert_response :success
      assert_select 'h1', text: /Platform administrator sign-in|Đăng nhập quản trị nền tảng/
      assert_select 'input[name=organization_slug]', count: 0
      assert_select 'nav.nav', count: 0
      assert_select 'a[href=?]', staff_members_path, count: 0
      post_with_csrf platform_sign_in_path, csrf_page: platform_sign_in_path,
        params: {email: @platform.email, password: PASS}
      assert_redirected_to platform_dashboard_path
      assert @platform.reload.last_sign_in_at.present?
      get platform_dashboard_path
      assert_response :success
      assert_select 'h1', text: /Platform overview|Tổng quan quản trị nền tảng/
      assert_select 'body', text: /Isolated Tenant/, count: 0
      assert_select 'a[href=?]', tickets_path, count: 0
      assert_select 'a[href=?]', staff_members_path, count: 0
    end
  end

  test 'platform login never grants tenant access, including when tenant password login is enabled' do
    platform_mode do
      tenant_password_mode do
        post_with_csrf platform_sign_in_path, csrf_page: platform_sign_in_path,
          params: {email: @platform.email, password: PASS}
        assert_redirected_to platform_dashboard_path
        get root_path
        assert_redirected_to password_sign_in_path
        get staff_members_path
        assert_redirected_to password_sign_in_path
        post_with_csrf password_sign_in_path, csrf_page: password_sign_in_path,
          params: {email: @platform.email, password: PASS, organization_slug: @tenant.slug}
        assert_response :unauthorized
      end
    end
  end

  test 'tenant owner cannot log into platform or create system administrator through tenant staff' do
    platform_mode do
      post_with_csrf platform_sign_in_path, csrf_page: platform_sign_in_path,
        params: {email: @owner_user.email, password: PASS}
      assert_response :unauthorized
    end
    demo_sign_in_owner
    count = PlatformAdmin.count
    post_with_csrf staff_members_path, params: {
      role: 'system_admin', email: 'forged-platform@example.test',
      display_name: 'Forbidden Operator', system_admin: true}
    assert_redirected_to staff_members_path
    assert_equal count, PlatformAdmin.count
    refute User.exists?(email: 'forged-platform@example.test')
    get staff_members_path
    assert_response :success
    assert_select 'body', text: /platform-operator@example.test/, count: 0
    assert_select 'select[name=role] option[value=system_admin]', count: 0
  end

  test 'platform and tenant identifiers cannot reuse the same email' do
    assert_raises(ActiveRecord::RecordInvalid) do
      PlatformAdmin.create!(email: @owner_user.email, password: PASS,
        display_name: 'Impersonated')
    end
    assert_raises(ActiveRecord::RecordInvalid) do
      User.create!(email: @platform.email, display_name: 'Wrong Scope')
    end
    assert_raises(ActiveRecord::RecordInvalid) do
      PlatformAdmin.create!(email: @platform.email.upcase, password: PASS,
        display_name: 'Duplicate Operator')
    end
  end

  test 'revoking platform operator immediately disables existing platform session' do
    platform_mode do
      post_with_csrf platform_sign_in_path, csrf_page: platform_sign_in_path,
        params: {email: @platform.email, password: PASS}
      assert_redirected_to platform_dashboard_path
      @platform.update!(active: false)
      get platform_dashboard_path
      assert_redirected_to platform_sign_in_path
      post_with_csrf platform_sign_in_path, csrf_page: platform_sign_in_path,
        params: {email: @platform.email, password: PASS}
      assert_response :unauthorized
    end
  end

  test 'signing out of platform destroys its session without changing tenant accounts' do
    platform_mode do
      post_with_csrf platform_sign_in_path, csrf_page: platform_sign_in_path,
        params: {email: @platform.email, password: PASS}
      assert_redirected_to platform_dashboard_path
      delete platform_sign_out_path, params: {},
        headers: csrf_headers_from(platform_dashboard_path)
      assert_redirected_to platform_sign_in_path
      get platform_dashboard_path
      assert_redirected_to platform_sign_in_path
      assert @owner.reload.active?
    end
  end

  private

  def platform_mode
    prev = ENV['P0_PLATFORM_AUTH_TEST_MODE']
    ENV['P0_PLATFORM_AUTH_TEST_MODE'] = 'YES'
    yield
  ensure
    prev ? ENV['P0_PLATFORM_AUTH_TEST_MODE'] = prev : ENV.delete('P0_PLATFORM_AUTH_TEST_MODE')
  end

  def tenant_password_mode
    prev = ENV['P0_PASSWORD_AUTH_TEST_MODE']
    ENV['P0_PASSWORD_AUTH_TEST_MODE'] = 'YES'
    yield
  ensure
    prev ? ENV['P0_PASSWORD_AUTH_TEST_MODE'] = prev : ENV.delete('P0_PASSWORD_AUTH_TEST_MODE')
  end

  def demo_sign_in_owner
    post_with_csrf demo_sign_in_path, csrf_page: demo_sign_in_path,
      params: {membership_id: @owner.id, locale: 'en'}
    assert_redirected_to root_path
  end
end
