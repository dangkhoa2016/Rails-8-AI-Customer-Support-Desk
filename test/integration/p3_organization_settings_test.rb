# frozen_string_literal: true
require 'test_helper'
require_relative '../support/csrf_requests'

class P3OrganizationSettingsTest < ActionDispatch::IntegrationTest
  include CsrfRequests

  setup do
    @tf = Organization.create!(slug: 'p3-settings-tf', name: 'Original Tenant',
      vertical: 'b2b_saas', currency: 'USD', timezone: 'Asia/Ho_Chi_Minh',
      default_locale: 'vi', policy_version: '1.0.0')
    @nm = Organization.create!(slug: 'p3-settings-nm', name: 'Other Tenant',
      vertical: 'ecommerce', currency: 'VND')
    @owner = member(@tf, 'owner', 'p3-owner@example.test')
    @admin = member(@tf, 'admin', 'p3-admin@example.test')
    @agent = member(@tf, 'agent', 'p3-agent@example.test')
    @viewer = member(@tf, 'viewer', 'p3-viewer@example.test')
  end

  test 'owner can update display settings only; policy, currency and tenant fields remain immutable' do
    login(@owner)
    patch_with_csrf organization_settings_path, params: {
      organization: {name: 'Updated Tenant Name', timezone: 'UTC', default_locale: 'en',
        currency: 'VND', vertical: 'ecommerce', policy_version: '99.0.0', slug: @nm.slug,
        id: @nm.id}}
    assert_redirected_to organization_settings_path
    assert_equal 'Updated Tenant Name', @tf.reload.name
    assert_equal 'UTC', @tf.timezone
    assert_equal 'en', @tf.default_locale
    assert_equal 'USD', @tf.currency
    assert_equal 'b2b_saas', @tf.vertical
    assert_equal '1.0.0', @tf.policy_version
    assert_equal 'Other Tenant', @nm.reload.name
    assert_equal 'organization.settings_changed', AuditEvent.last.action
  end

  test 'admin sees tenant settings but cannot change them' do
    login(@admin)
    get organization_settings_path
    assert_response :success
    assert_select 'h1', text: /Organization settings|Cấu hình doanh nghiệp/
    assert_select 'input[type=submit]', count: 0
    patch_with_csrf organization_settings_path,
      params: {organization: {name: 'Forbidden', timezone: 'UTC', default_locale: 'en'}}
    assert_response :forbidden
    assert_equal 'Original Tenant', @tf.reload.name
  end

  test 'agents and viewers cannot read or change organization settings' do
    [@agent, @viewer].each do |identity|
      login(identity)
      get organization_settings_path
      assert_response :forbidden
      patch_with_csrf organization_settings_path,
        params: {organization: {name: 'Forbidden', timezone: 'UTC', default_locale: 'en'}}
      assert_response :forbidden
    end
    assert_equal 'Original Tenant', @tf.reload.name
  end

  test 'invalid timezone, locale and blank names are rejected' do
    login(@owner)
    [
      {name: 'X', timezone: 'UTC', default_locale: 'en'},
      {name: 'Valid Company', timezone: 'Invalid/Zone', default_locale: 'en'},
      {name: 'Valid Company', timezone: 'UTC', default_locale: 'xx'}
    ].each do |bad|
      patch_with_csrf organization_settings_path, params: {organization: bad}
      assert_redirected_to organization_settings_path
      assert_equal 'Original Tenant', @tf.reload.name
    end
    assert_equal 0, AuditEvent.count
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
