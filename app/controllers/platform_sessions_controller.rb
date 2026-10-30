# frozen_string_literal: true

# Independent platform login; sandbox requires a replay-protected second factor.
class PlatformSessionsController < ApplicationController
  skip_before_action :require_demo_session
  layout 'platform'
  helper_method :platform_auth_mode?
  before_action :require_platform_auth_mode
  rate_limit to: (Rails.env.test? ? 100 : 5), within: 15.minutes,
    only: :create, name: 'password', by: -> { request.remote_ip.to_s },
    if: -> { !Rails.env.sandbox? },
    with: -> { head :too_many_requests }
  rate_limit to: (Rails.env.test? ? 100 : 5), within: 15.minutes,
    only: :verify_mfa, name: 'mfa', by: -> { request.remote_ip.to_s },
    if: -> { !Rails.env.sandbox? },
    with: -> { head :too_many_requests }

  before_action :enforce_sandbox_throttle, only: [:create, :verify_mfa]

  def new
    # A fresh password attempt must invalidate an old pending MFA challenge.
    session.delete(:platform_pending_admin_id)
    session.delete(:platform_pending_at)
    session.delete(:platform_pending_version)
  end

  def create
    email = params[:email].to_s.strip.downcase
    password = params[:password].to_s
    admin = if email.length.between?(3, 254) && password.length <= 200
      PlatformAdmin.find_by(email: email)
    end
    unless admin&.password_login_eligible? && admin.authenticate(password)
      admin&.record_failed_password! if admin&.active? && admin.locked_until.to_i <= Time.current.to_i
      security_event!('platform.login.password_rejected', admin)
      return rejected
    end
    admin.clear_failed_password!
    if platform_mfa_required?
      return rejected unless admin.mfa_enrolled?
      reset_session
      session[:platform_pending_admin_id] = admin.id
      session[:platform_pending_at] = Time.current.to_i
      session[:platform_pending_version] = admin.session_version
      security_event!('platform.login.password_valid', admin)
      return redirect_to platform_mfa_path, status: :see_other
    end

    finish_login!(admin)
  end

  def mfa
    return head :forbidden unless platform_mfa_required?
    redirect_to platform_sign_in_path unless pending_admin
  end

  def verify_mfa
    return head :forbidden unless platform_mfa_required?
    admin = pending_admin
    unless admin&.verify_mfa_once!(params[:code].to_s)
      security_event!('platform.login.mfa_rejected', admin)
      flash.now[:alert] = t('platform_mfa.invalid')
      return render :mfa, status: :unauthorized
    end
    finish_login!(admin)
  end

  def destroy
    reset_session
    redirect_to platform_sign_in_path, status: :see_other
  end

  private

  def enforce_sandbox_throttle
    return unless Rails.env.sandbox? ||
      (Rails.env.test? && ENV['P03_THROTTLE_TEST_MODE'] == 'YES')
    scope = action_name == 'create' ? 'password' : 'mfa'
    return if PlatformLoginThrottle.allow?(scope: scope, address: request.remote_ip.to_s)
    security_event!('platform.login.throttled', nil)
    head :too_many_requests
  end

  def platform_mfa_required?
    Rails.env.sandbox? || (Rails.env.test? && ENV['P03_MFA_TEST_MODE'] == 'YES')
  end

  def pending_admin
    return nil unless session[:platform_pending_at].to_i.between?(5.minutes.ago.to_i, Time.current.to_i)
    admin = PlatformAdmin.find_by(id: session[:platform_pending_admin_id], active: true)
    return nil unless admin && session[:platform_pending_version] == admin.session_version
    admin
  end

  def finish_login!(admin)
    reset_session
    session[:platform_admin_id] = admin.id
    session[:locale] = I18n.locale
    if platform_mfa_required?
      session[:platform_session_started_at] = Time.current.to_i
      session[:platform_session_last_seen_at] = Time.current.to_i
      session[:platform_session_version] = admin.session_version
    end
    admin.update_column(:last_sign_in_at, Time.current)
    security_event!('platform.login.completed', admin) if platform_mfa_required?
    redirect_to platform_dashboard_path, status: :see_other
  end

  def security_event!(event_type, admin)
    return unless platform_mfa_required?
    PlatformSecurityEvent.create!(platform_admin: admin, event_type: event_type,
      request_id: request.request_id)
  end

  def rejected
    flash.now[:alert] = t('auth.invalid_user')
    render :new, status: :unauthorized
  end

  def require_platform_auth_mode
    head :forbidden unless platform_auth_mode?
  end
end
