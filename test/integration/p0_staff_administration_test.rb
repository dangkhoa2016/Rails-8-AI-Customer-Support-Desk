# frozen_string_literal: true
require 'test_helper'
require_relative '../support/csrf_requests'

class P0StaffAdministrationTest < ActionDispatch::IntegrationTest
  include CsrfRequests

  setup do
    @tf = Organization.create!(slug: 'p0-tf-staff', name: 'P0 TeamFlow', vertical: 'b2b_saas', currency: 'USD')
    @nm = Organization.create!(slug: 'p0-nm-staff', name: 'P0 NovaMart', vertical: 'ecommerce', currency: 'VND')
    @owner = member(@tf, 'owner', 'staff-owner@example.test')
    @admin = member(@tf, 'admin', 'staff-admin@example.test')
    @agent = member(@tf, 'agent', 'staff-agent@example.test')
    @viewer = member(@tf, 'viewer', 'staff-viewer@example.test')
    @other = member(@nm, 'agent', 'staff-other@example.test')
  end

  test 'owner sees only their tenant and inactive provisioning forms' do
    login(@owner)
    get staff_members_path
    assert_response :success
    assert_select 'h1', text: /Team & access|Nhân viên/
    assert_select 'body', text: /staff-agent@example.test/
    assert_select 'body', text: /staff-other@example.test/, count: 0
    assert_select 'form[action=?]', staff_members_path, count: 1
  end

  test 'agent and viewer cannot enumerate, create or modify staff' do
    [@agent, @viewer].each do |identity|
      login(identity)
      get staff_members_path
      assert_response :forbidden
      post_with_csrf staff_members_path, params: {email: 'deny@example.test', display_name: 'Deny', role: 'agent'}
      assert_response :forbidden
      patch_with_csrf staff_member_path(@admin), params: {role: 'agent', active: '0'}
      assert_response :forbidden
    end
  end

  test 'owner provisions only inactive new user with audit and no default password' do
    login(@owner)
    post_with_csrf staff_members_path,
      params: {email: 'New.Staff@example.test', display_name: 'New Staff', role: 'admin'}
    assert_redirected_to staff_members_path
    person = User.find_by!(email: 'new.staff@example.test')
    assert_nil person.password_digest
    refute person.system_admin?
    record = Membership.find_by!(organization: @tf, user: person)
    assert_equal 'admin', record.role
    refute record.active?
    assert_equal 'staff.provisioned_inactive', AuditEvent.last.action
  end

  test 'admin may manage agents and viewers but never owners or peer admins' do
    login(@admin)
    patch_with_csrf staff_member_path(@agent), params: {role: 'viewer', active: '0'}
    assert_redirected_to staff_members_path
    assert_equal 'viewer', @agent.reload.role
    refute @agent.active?
    assert_equal 'staff.membership_changed', AuditEvent.last.action
    patch_with_csrf staff_member_path(@owner), params: {role: 'viewer', active: '0'}
    assert_response :forbidden
    assert_equal 'owner', @owner.reload.role
    patch_with_csrf staff_member_path(@admin), params: {role: 'agent', active: '0'}
    assert_response :forbidden
    assert_equal 'admin', @admin.reload.role
    post_with_csrf staff_members_path,
      params: {email: 'forbidden-admin@example.test', display_name: 'Bad Admin', role: 'admin'}
    assert_redirected_to staff_members_path
    assert_nil User.find_by(email: 'forbidden-admin@example.test')
  end

  test 'same email in global identity table cannot be taken over by second tenant' do
    login(@owner)
    post_with_csrf staff_members_path,
      params: {email: @other.user.email, display_name: 'Someone Else', role: 'agent'}
    assert_redirected_to staff_members_path
    assert_nil Membership.find_by(user_id: @other.user_id, organization_id: @tf.id)
  end

  test 'forged cross-tenant membership cannot be changed and owner cannot self-demote' do
    login(@owner)
    patch_with_csrf staff_member_path(@other), params: {role: 'viewer', active: '0'}
    assert_response :not_found
    assert @other.reload.active?
    patch_with_csrf staff_member_path(@owner), params: {role: 'agent', active: '0'}
    assert_response :forbidden
    assert_equal 'owner', @owner.reload.role
    assert @owner.active?
  end

  private

  def member(org, role, email)
    user = User.create!(email: email, display_name: "#{role} sample")
    Membership.create!(organization: org, user: user, role: role)
  end

  def login(identity)
    post_with_csrf demo_sign_in_path, csrf_page: demo_sign_in_path,
      params: {membership_id: identity.id, locale: 'en'}
    assert_redirected_to root_path
  end
end
