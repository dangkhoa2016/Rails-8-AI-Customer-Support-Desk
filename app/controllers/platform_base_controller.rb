# frozen_string_literal: true

# Never inherit tenant authorization on platform endpoints.
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
    unless platform_admin&.password_login_eligible? && valid_platform_session?
      reset_session
      return redirect_to platform_sign_in_path
    end
  end

  def valid_platform_session?
    return true unless Rails.env.sandbox? || (Rails.env.test? && ENV['P03_MFA_TEST_MODE'] == 'YES')
    now = Time.current.to_i
    started = session[:platform_session_started_at].to_i
    last = session[:platform_session_last_seen_at].to_i
    return false unless started.positive? && last.positive? &&
      started <= now && last <= now &&
      now - started <= 8.hours.to_i && now - last <= 15.minutes.to_i &&
      session[:platform_session_version] == platform_admin.session_version
    session[:platform_session_last_seen_at] = now
    true
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
