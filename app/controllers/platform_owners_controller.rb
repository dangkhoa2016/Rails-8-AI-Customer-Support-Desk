# frozen_string_literal: true

# Owner membership administration is a platform-scoped lifecycle operation.
# This is NOT user impersonation, credential provisioning or tenant staff CRUD.
class PlatformOwnersController < PlatformBaseController
  def create
    org = Organization.find(params[:organization_id])
    email = params[:email].to_s.strip.downcase
    name = params[:display_name].to_s.strip
    unless email.match?(/\A[^\s@]+@[^\s@]+\.[^\s@]+\z/) &&
      email.length <= 254 && name.length.between?(2, 120)
      return redirect_to platform_organization_path(org),
        alert: t('platform_mgmt.owner_invalid'), status: :see_other
    end
    # Existing users are never linked cross-tenant by email; no platform operator
    # identity may be reused as a tenant user. No invitation is sent.
    unless User.where('LOWER(email) = ?', email).none? &&
      PlatformAdmin.where('LOWER(email) = ?', email).none?
      return redirect_to platform_organization_path(org),
        alert: t('platform_mgmt.owner_exists'), status: :see_other
    end
    ActiveRecord::Base.transaction do
      user = User.create!(email: email, display_name: name, active: true)
      member = Membership.create!(organization: org, user: user,
        role: 'owner', active: false)
      platform_audit!(action: 'platform.owner.provisioned_inactive',
        organization: org, target: member,
        metadata: {membership_id: member.id, target_role: 'owner', active: false})
    end
    redirect_to platform_organization_path(org),
      notice: t('platform_mgmt.owner_created'), status: :see_other
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    redirect_to platform_organization_path(org),
      alert: t('platform_mgmt.owner_invalid'), status: :see_other
  end

  def update
    org = Organization.find(params[:organization_id])
    member = Membership.where(organization_id: org.id, role: 'owner')
      .includes(:user).find(params[:id])
    desired = params[:active].to_s
    return head :unprocessable_entity unless %w[0 1].include?(desired)

    desired_active = desired == '1'
    ActiveRecord::Base.transaction do
      org.lock!
      member.lock!
      if member.active? != desired_active
        if desired_active
          # Prevent activation of identities without verified credentials.
          return head :unprocessable_entity unless member.user.active? &&
            member.user.password_digest.present?
        elsif org.active_for_support?
          # Never leave a live tenant with zero enabled owners.
          count = Membership.where(organization_id: org.id,
            role: 'owner', active: true).count
          return head :unprocessable_entity if count <= 1
        end
        original = member.active?
        member.update!(active: desired_active)
        platform_audit!(action: 'platform.owner.active_changed',
          organization: org, target: member,
          metadata: {membership_id: member.id, target_role: 'owner',
            from_state: original ? 'active' : 'inactive',
            to_state: desired_active ? 'active' : 'inactive'})
      end
    end
    redirect_to platform_organization_path(org),
      notice: t('platform_mgmt.owner_updated'), status: :see_other
  end
end
