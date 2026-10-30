# frozen_string_literal: true
class PlatformDashboardController < PlatformBaseController
  def index
    @organization_count = Organization.count
    @active_organizations = Organization.where(lifecycle_state: 'active').count
    @staged_organizations = Organization.where(lifecycle_state: 'staging').count
    @suspended_organizations = Organization.where(lifecycle_state: 'suspended').count
    @user_count = User.count
    @active_memberships = Membership.where(active: true).count
    @audit_count = PlatformAuditEvent.count
  end
end
