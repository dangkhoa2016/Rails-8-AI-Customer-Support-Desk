# frozen_string_literal: true

# Completely independent session and credential store from tenant authentication.
# No demo sign-in, self-registration, impersonation or default platform account.
class PlatformSessionsController < ApplicationController
  skip_before_action :require_demo_session
  layout 'platform'
  helper_method :platform_auth_mode?
  before_action :require_platform_auth_mode
  rate_limit to: (Rails.env.test? ? 100 : 5), within: 15.minutes,
    only: :create, by: -> { request.remote_ip.to_s },
    with: -> { head :too_many_requests }

  def new
  end

  def create
    email = params[:email].to_s.strip.downcase
    password = params[:password].to_s
    admin = if email.length.between?(3, 254) && password.length <= 200
      PlatformAdmin.find_by(email: email)
    end
    return rejected unless admin&.password_login_eligible? && admin.authenticate(password)

    reset_session
    session[:platform_admin_id] = admin.id
    session[:locale] = I18n.locale
    admin.update_column(:last_sign_in_at, Time.current)
    redirect_to platform_dashboard_path, status: :see_other
  end

  def destroy
    reset_session
    redirect_to platform_sign_in_path, status: :see_other
  end

  private

  def rejected
    flash.now[:alert] = t('auth.invalid_user')
    render :new, status: :unauthorized
  end

  def require_platform_auth_mode
    head :forbidden unless platform_auth_mode?
  end
end
