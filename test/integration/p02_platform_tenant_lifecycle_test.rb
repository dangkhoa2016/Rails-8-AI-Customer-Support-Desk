# frozen_string_literal: true
require 'test_helper'
require_relative '../support/csrf_requests'

class P02PlatformTenantLifecycleTest < ActionDispatch::IntegrationTest
  include CsrfRequests
  PASS = 'p02-platform-security-password-2026!'

  setup do
    @tf = Organization.create!(slug: 'p02-teamflow', name: 'TeamFlow Sample',
      vertical: 'b2b_saas', currency: 'USD', policy_version: '1.0.0')
    @nm = Organization.create!(slug: 'p02-novamart', name: 'NovaMart Sample',
      vertical: 'ecommerce', currency: 'VND', policy_version: '1.0.0')
    @owner_user = User.create!(email: 'p02-owner@example.test',
      display_name: 'Sample Owner', password: PASS)
    @owner = Membership.create!(organization: @tf, user: @owner_user, role: 'owner')
    @platform = PlatformAdmin.create!(email: 'p02-platform@example.test',
      display_name: 'Platform Operator', password: PASS)
  end

  test 'all management routes are disabled by default and inaccessible to tenant owners' do
    get platform_organizations_path
    assert_response :forbidden
    get platform_audit_events_path
    assert_response :forbidden
    demo_login(@owner)
    get platform_organizations_path
    assert_response :forbidden
    get platform_organization_path(@tf)
    assert_response :forbidden
  end

  test 'platform has scoped organization list and independent navigation without tenant tickets' do
    platform_mode do
      login_platform
      get platform_organizations_path
      assert_response :success
      assert_select 'a[href=?]', new_platform_organization_path
      assert_select 'body', text: /p02-teamflow/
      assert_select 'a[href=?]', tickets_path, count: 0
      get platform_organization_path(@tf)
      assert_response :success
      assert_select 'input[name=?]', 'organization[name]', count: 1
      get platform_audit_events_path
      assert_response :success
      assert_select 'h1', text: /Platform audit logs|Nhật ký quản trị nền tảng/
    end
  end

  test 'creating organization starts staged with PENDING policy, no owner, and one audit event' do
    platform_mode do
      login_platform
      post_with_csrf platform_organizations_path, csrf_page: new_platform_organization_path,
        params: {organization: {slug: 'p02-new-business',
          name: 'Staged Business', vertical: 'ecommerce', currency: 'VND',
          timezone: 'UTC', default_locale: 'en', policy_version: '1.0.0',
          lifecycle_state: 'active'}}
      created = Organization.find_by!(slug: 'p02-new-business')
      assert_redirected_to platform_organization_path(created)
      assert_equal 'staging', created.lifecycle_state
      assert_equal 'PENDING', created.policy_version
      assert_equal 0, Membership.where(organization_id: created.id).count
      assert_equal 'platform.organization.created_staging', PlatformAuditEvent.last.action
      assert_equal @platform.id, PlatformAuditEvent.last.platform_admin_id
      assert_equal 1, PlatformAuditEvent.where(organization_id: created.id).count
      patch_with_csrf lifecycle_platform_organization_path(created),
        params: {lifecycle_state: 'active'}
      assert_response :unprocessable_entity
      assert_equal 'staging', created.reload.lifecycle_state
    end
  end

  test 'display update cannot change slug, currency, policy, vertical or lifecycle' do
    platform_mode do
      login_platform
      patch_with_csrf platform_organization_path(@tf),
        params: {organization: {name: 'Updated TeamFlow', timezone: 'UTC',
          default_locale: 'en', slug: 'forged', currency: 'VND',
          vertical: 'ecommerce', policy_version: '999', lifecycle_state: 'suspended'}}
      assert_redirected_to platform_organization_path(@tf)
      assert_equal 'Updated TeamFlow', @tf.reload.name
      assert_equal 'UTC', @tf.timezone
      assert_equal 'en', @tf.default_locale
      assert_equal 'p02-teamflow', @tf.slug
      assert_equal 'USD', @tf.currency
      assert_equal 'b2b_saas', @tf.vertical
      assert_equal '1.0.0', @tf.policy_version
      assert_equal 'active', @tf.lifecycle_state
      audit = PlatformAuditEvent.last
      assert_equal 'platform.organization.display_changed', audit.action
      assert_equal %w[name timezone default_locale].sort, audit.metadata.fetch('changed_keys').sort
    end
  end

  test 'suspension revokes existing tenant session and is audited' do
    demo_login(@owner)
    get root_path
    assert_response :success
    platform_mode do
      login_platform
      patch_with_csrf lifecycle_platform_organization_path(@tf),
        params: {lifecycle_state: 'suspended'}
      assert_redirected_to platform_organization_path(@tf)
      assert_equal 'suspended', @tf.reload.lifecycle_state
      assert_equal 'platform.organization.lifecycle_changed', PlatformAuditEvent.last.action
    end
    demo_login(@owner)
    get root_path
    assert_redirected_to demo_sign_in_path
    assert_equal 'suspended', @tf.reload.lifecycle_state
  end

  test 'reactivation requires approved policy content and at least one active owner' do
    platform_mode do
      login_platform
      patch_with_csrf lifecycle_platform_organization_path(@tf),
        params: {lifecycle_state: 'suspended'}
      patch_with_csrf lifecycle_platform_organization_path(@tf),
        params: {lifecycle_state: 'active'}
      assert_response :unprocessable_entity
      assert_equal 'suspended', @tf.reload.lifecycle_state
    end
  end

  test 'owner provisioning is inactive, does not reuse tenant or platform identities, and cannot self-activate' do
    platform_mode do
      login_platform
      post_with_csrf platform_organization_owners_path(@tf),
        params: {display_name: 'New Owner', email: 'p02-inactive@example.test',
          role: 'system_admin', active: '1'}
      assert_redirected_to platform_organization_path(@tf)
      user = User.find_by!(email: 'p02-inactive@example.test')
      member = Membership.find_by!(organization_id: @tf.id, user_id: user.id)
      refute member.active?
      assert_equal 'owner', member.role
      assert_nil user.password_digest
      assert_equal 'platform.owner.provisioned_inactive', PlatformAuditEvent.last.action
      patch_with_csrf platform_organization_owner_path(@tf, member), params: {active: '1'}
      assert_response :unprocessable_entity
      assert !member.reload.active?
      post_with_csrf platform_organization_owners_path(@tf),
        params: {display_name: 'Duplicate', email: @platform.email}
      assert_nil User.find_by(email: @platform.email)
      assert_equal 1, Membership.where(organization_id: @tf, role: 'owner').where(active: false).count
    end
  end

  test 'active tenant cannot lose its last active owner' do
    platform_mode do
      login_platform
      patch_with_csrf platform_organization_owner_path(@tf, @owner), params: {active: '0'}
      assert_response :unprocessable_entity
      assert @owner.reload.active?
      assert_equal 0, PlatformAuditEvent.count
    end
  end

  test 'platform can deactivate second owner and record safe append-only event' do
    second = User.create!(email: 'p02-other-owner@example.test',
      display_name: 'Second Owner', password: PASS)
    membership = Membership.create!(organization: @tf, user: second, role: 'owner')
    platform_mode do
      login_platform
      patch_with_csrf platform_organization_owner_path(@tf, membership),
        params: {active: '0'}
      assert_redirected_to platform_organization_path(@tf)
      refute membership.reload.active?
      assert @owner.reload.active?
      audit = PlatformAuditEvent.last
      assert_equal 'platform.owner.active_changed', audit.action
      assert_equal 'inactive', audit.metadata.fetch('to_state')
      assert_raises(ActiveRecord::ReadOnlyRecord) { audit.update!(action: 'tampered') }
      get platform_audit_events_path
      assert_response :success
      assert_select 'body', text: /platform.owner.active_changed/
      assert_select 'body', text: /p02-other-owner@example.test/, count: 0
    end
  end

  test 'audit filters are scoped to platform and never reveal tenant ticket contents' do
    platform_mode do
      login_platform
      patch_with_csrf platform_organization_path(@tf),
        params: {organization: {name: 'Name Revision', timezone: 'UTC',
          default_locale: 'vi'}}
      get platform_audit_events_path(action_filter: 'platform.organization.display_changed',
        organization_id: @tf.id.to_s)
      assert_response :success
      assert_select 'body', text: /platform.organization.display_changed/
      assert_select 'body', text: /internal customer message/, count: 0
      get platform_audit_events_path(action_filter: 'unexpected', organization_id: '2 OR 1=1')
      assert_response :success
    end
  end

  test 'reactivation succeeds after approved policy evidence and active owner' do
    article = KnowledgeArticle.create!(organization: @tf,
      article_key: 'P02-KB-ACTIVE', category: 'billing_subscription',
      audience: 'public', policy_refs: [])
    body = 'Synthetic approved policy evidence for platform lifecycle testing.'
    KnowledgeArticleVersion.create!(organization: @tf, knowledge_article: article,
      locale: 'en', version_number: 1, title: 'Lifecycle evidence',
      body: body, sha256: Digest::SHA256.hexdigest(body),
      source_blueprint_sha256: 'p02-test-only', status: 'approved',
      policy_version: @tf.policy_version, effective_from: Date.yesterday,
      approved_by: @owner_user.id, approved_at: Time.current)
    platform_mode do
      login_platform
      patch_with_csrf lifecycle_platform_organization_path(@tf),
        params: {lifecycle_state: 'suspended'}
      assert_equal 'suspended', @tf.reload.lifecycle_state
      patch_with_csrf lifecycle_platform_organization_path(@tf),
        params: {lifecycle_state: 'active'}
      assert_redirected_to platform_organization_path(@tf)
      assert_equal 'active', @tf.reload.lifecycle_state
      assert_equal 2, PlatformAuditEvent.where(
        action: 'platform.organization.lifecycle_changed').count
      assert SupportDeskAccessPolicy.new(@owner).allowed?(:ticket_read)
    end
  end

  test 'verified second Owner can be enabled without changing tenant permissions' do
    second_user = User.create!(email: 'p02-enable-owner@example.test',
      display_name: 'Verified Second Owner', password: PASS)
    second_member = Membership.create!(organization: @tf,
      user: second_user, role: 'owner', active: false)
    platform_mode do
      login_platform
      patch_with_csrf platform_organization_owner_path(@tf, second_member),
        params: {active: '1', role: 'system_admin', organization_id: @nm.id}
      assert_redirected_to platform_organization_path(@tf)
      assert second_member.reload.active?
      assert_equal 'owner', second_member.role
      assert_equal @tf.id, second_member.organization_id
      assert_equal 'platform.owner.active_changed', PlatformAuditEvent.last.action
      assert_equal 0, PlatformAdmin.where(email: second_user.email).count
    end
  end

  private

  # Platform forms must obtain their CSRF token from a platform page,
  # not the unrelated tenant root which correctly redirects to demo login.
  def patch_with_csrf(path, params:, csrf_page: nil)
    super(path, params: params, csrf_page: csrf_page || platform_dashboard_path)
  end

  def post_with_csrf(path, params:, csrf_page: nil)
    super(path, params: params, csrf_page: csrf_page || platform_dashboard_path)
  end

  def platform_mode
    previous = ENV['P0_PLATFORM_AUTH_TEST_MODE']
    ENV['P0_PLATFORM_AUTH_TEST_MODE'] = 'YES'
    yield
  ensure
    previous ? ENV['P0_PLATFORM_AUTH_TEST_MODE'] = previous : ENV.delete('P0_PLATFORM_AUTH_TEST_MODE')
  end

  def login_platform
    post_with_csrf platform_sign_in_path, csrf_page: platform_sign_in_path,
      params: {email: @platform.email, password: PASS}
    assert_redirected_to platform_dashboard_path
  end

  def demo_login(member)
    post_with_csrf demo_sign_in_path, csrf_page: demo_sign_in_path,
      params: {membership_id: member.id, locale: 'en'}
  end
end
