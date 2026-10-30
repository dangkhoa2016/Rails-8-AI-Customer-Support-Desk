# frozen_string_literal: true

# Global platform administration is a separate authentication scope.
# Listing organizations does NOT authorize access to tenant tickets or internal notes.
class PlatformDashboardController < ApplicationController
  skip_before_action :require_demo_session
  before_action :require_platform_admin

  def index
    @organization_count = Organization.count
    @user_count = User.count
    @active_memberships = Membership.where(active: true).count
  end

  private

  def require_platform_admin
    return head :forbidden unless password_auth_mode?
    user = User.find_by(id: session[:platform_user_id], active: true, system_admin: true)
    head :forbidden unless user&.password_login_eligible?
  end
end
