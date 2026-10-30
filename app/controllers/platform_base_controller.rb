# frozen_string_literal: true

# Never inherit tenant ApplicationController authorization on platform endpoints.
# All platform operations use an independent PlatformAdmin session and policy.
class PlatformBaseController < ApplicationController
  skip_before_action :require_demo_session
  layout 'platform'
  before_action :require_platform_admin

  helper_method :platform_admin, :platform_auth_mode?

  private

  def platform_admin
    return @platform_admin if defined?(@platform_admin)
    @platform_admin = PlatformAdmin.find_by(id: session[:platform_admin_id], active: true)
  end

  def require_platform_admin
    return head :forbidden unless platform_auth_mode?
    redirect_to platform_sign_in_path unless platform_admin&.password_login_eligible?
  end

  def platform_audit!(action:, organization: nil, target:, metadata: {})
    raise SecurityError, 'unauthenticated platform operation' unless platform_admin
    raise ArgumentError, 'unapproved audit fields' unless metadata.keys.all? do |key|
      %w[from_state to_state changed_keys membership_id target_role active].include?(key.to_s)
    end
    PlatformAuditEvent.create!(
      platform_admin: platform_admin, organization: organization,
      target_type: target.class.name, target_id: target.id, action: action,
      metadata: metadata, request_id: request.request_id
    )
  end
end
