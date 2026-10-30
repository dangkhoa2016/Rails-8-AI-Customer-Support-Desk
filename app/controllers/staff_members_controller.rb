# frozen_string_literal: true

# Tenant-local staff administration. Existing cross-tenant users are never silently linked.
# No invitation is sent: newly provisioned accounts remain inactive until explicit activation.
class StaffMembersController < ApplicationController
  before_action -> { require_permission(:staff_read) }
  before_action -> { require_permission(:staff_manage) }, only: %i[create update]

  def index
    @members = Membership.includes(:user).where(organization_id: current_organization.id)
      .order(:role, :id)
    @creatable_roles = current_membership.role == 'owner' ?
      %w[admin agent viewer] : %w[agent viewer]
  end

  def create
    role = params[:role].to_s
    email = params[:email].to_s.strip.downcase
    name = params[:display_name].to_s.strip
    unless creatable_role?(role) && email.match?(/\A[^\s@]+@[^\s@]+\.[^\s@]+\z/) &&
        email.length <= 254 && name.length.between?(2, 100)
      return redirect_to staff_members_path, alert: t('staff.invalid'), status: :see_other
    end

    # Never reuse an existing global user by email without a verified invitation.
    # The unique user email index also guards concurrent duplicate creation.
    unless User.where('LOWER(email) = ?', email).none?
      return redirect_to staff_members_path, alert: t('staff.existing'), status: :see_other
    end
    ActiveRecord::Base.transaction do
      user = User.create!(email: email, display_name: name, active: true)
      member = Membership.create!(organization: current_organization,
        user: user, role: role, active: false)
      audit!(action: 'staff.provisioned_inactive', metadata: {
        membership_id: member.id, target_user_id: user.id, role: role})
    end
    redirect_to staff_members_path, notice: t('staff.created_inactive'), status: :see_other
  rescue ActiveRecord::RecordNotUnique
    redirect_to staff_members_path, alert: t('staff.existing'), status: :see_other
  end

  def update
    member = Membership.where(organization_id: current_organization.id)
      .includes(:user).find(params[:id])
    desired_role = params[:role].to_s
    desired_active = params[:active] == '1'
    # Ownership transfers require a separate, protected procedure.
    if member.role == 'owner' || member.user_id == current_user.id ||
        !access_policy.may_manage_membership?(
          target_role: member.role, new_role: desired_role)
      return head :forbidden
    end
    ActiveRecord::Base.transaction do
      member.lock!
      previous = {role: member.role, active: member.active?}
      member.update!(role: desired_role, active: desired_active)
      audit!(action: 'staff.membership_changed', metadata: {
        membership_id: member.id, target_user_id: member.user_id,
        from: previous, to: {role: member.role, active: member.active?}})
    end
    redirect_to staff_members_path, notice: t('staff.updated'), status: :see_other
  end

  private

  def creatable_role?(role)
    roles = current_membership.role == 'owner' ?
      %w[admin agent viewer] : %w[agent viewer]
    roles.include?(role)
  end
end
