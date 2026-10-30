# frozen_string_literal: true
require 'test_helper'
require_relative '../support/csrf_requests'

class DemoAccountRoleGuideTest < ActionDispatch::IntegrationTest
  include CsrfRequests

  setup do
    @tf = Organization.create!(slug: 'guide-tf', name: 'Guide TeamFlow', vertical: 'b2b_saas', currency: 'USD')
    @nm = Organization.create!(slug: 'guide-nm', name: 'Guide NovaMart', vertical: 'ecommerce', currency: 'VND')
    @memberships = {}
    [@tf, @nm].each do |organization|
      %w[viewer agent owner].each do |role|
        user = User.create!(email: "guide-#{organization.slug}-#{role}@example.test", display_name: "Guide #{role.capitalize}")
        @memberships[[organization.slug, role]] = Membership.create!(organization: organization, user: user, role: role)
      end
    end
  end

  test 'Vietnamese account selector is grouped by organization and explains three roles' do
    get demo_sign_in_path(locale: 'vi')
    assert_response :success
    assert_select 'html[lang=vi]'
    assert_select 'select[name=membership_id][aria-describedby=demo-role-help] optgroup', count: 2
    assert_select 'select[name=membership_id] optgroup[label="Guide TeamFlow"] option', count: 3
    assert_select 'select[name=membership_id] optgroup[label="Guide NovaMart"] option', count: 3
    assert_select 'select[name=membership_id] option', count: 6
    assert_select 'article.demo-role-card', count: 3
    assert_select '#demo-role-guide-title', text: /Ba vai trò/
    assert_select '#demo-steps-title', text: /Hướng dẫn/
    assert_select 'ol.demo-test-steps li', count: 3
    assert_select 'body', text: /Viewer · Chỉ xem/
    assert_select 'body', text: /Agent · Nhân viên hỗ trợ/
    assert_select 'body', text: /Owner · Quản lý/
    assert_select 'body', text: /Cloudflare Private Demo/
    assert_select 'body', text: /Answerability/
  end

  test 'English help explains role restrictions and read-only tunnel' do
    get demo_sign_in_path(locale: 'en')
    assert_response :success
    assert_select 'html[lang=en]'
    assert_select '#demo-role-guide-title', text: /Three roles/
    assert_select 'article.demo-role-card', count: 3
    assert_select 'body', text: /Read only/
    assert_select 'body', text: /Support staff/
    assert_select 'body', text: /Manager/
    assert_select 'body', text: /blocked over the tunnel/
    assert_select 'body', text: /Answerability remains blocked/
    assert_select 'select[name=locale] option[selected][value=en]', count: 1
    assert_select 'select[name=membership_id] optgroup', count: 2
  end

  test 'switch account clears session and returns to grouped account picker' do
    viewer = @memberships.fetch(['guide-tf', 'viewer'])
    post_with_csrf demo_sign_in_path,
      params: {membership_id: viewer.id, locale: 'vi'}, csrf_page: demo_sign_in_path
    assert_redirected_to root_path
    get root_path
    assert_response :success
    assert_select 'form[action=?][method=post]', demo_sign_out_path do
      assert_select 'input[name=_method][value=delete]', count: 1
    end
    delete demo_sign_out_path, headers: csrf_headers_from(root_path)
    assert_redirected_to demo_sign_in_path
    get root_path
    assert_redirected_to demo_sign_in_path
    get demo_sign_in_path
    assert_response :success
    assert_select 'select[name=membership_id] option', count: 6
  end

  test 'selecting different roles still preserves selected tenant session' do
    viewer = @memberships.fetch(['guide-tf', 'viewer'])
    owner = @memberships.fetch(['guide-nm', 'owner'])
    post_with_csrf demo_sign_in_path, params: {membership_id: viewer.id, locale: 'vi'}, csrf_page: demo_sign_in_path
    assert_redirected_to root_path
    get root_path
    assert_response :success
    assert_select 'nav', text: /Guide TeamFlow · viewer/
    post_with_csrf demo_sign_in_path, params: {membership_id: owner.id, locale: 'en'}, csrf_page: demo_sign_in_path
    assert_redirected_to root_path
    get root_path
    assert_response :success
    assert_select 'nav', text: /Guide NovaMart · owner/
    assert_select 'nav', text: /Guide TeamFlow/, count: 0
  end
end
