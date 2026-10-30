# frozen_string_literal: true
# Production password-based sign-in is opt-in and independent of synthetic demo sessions.
# No self-registration, impersonation, password reset or default credentials.
class PasswordSessionsController < ApplicationController
  skip_before_action :require_demo_session
  before_action :require_password_mode
  rate_limit to: (Rails.env.test? ? 100 : 5), within: 15.minutes, only: :create,
    by: -> { request.remote_ip.to_s }, with: -> { head :too_many_requests }

  def new
  end

  def create
    email = params[:email].to_s.strip.downcase
    password = params[:password].to_s
    organization_slug = params[:organization_slug].to_s.strip
    # No user enumeration. No secrets or raw email/passwords in logs.
    user = (email.length <= 254 && password.length <= 200) ?
      User.where('LOWER(email) = ?', email).first : nil
    unless user&.password_login_eligible? && user.authenticate(password)
      return rejected
    end

    if organization_slug.blank? && user.system_admin?
      reset_session
      session[:platform_user_id] = user.id
      return redirect_to platform_dashboard_path, status: :see_other
    end

    organization = Organization.find_by(slug: organization_slug)
    membership = organization && Membership.find_by(
      organization_id: organization.id, user_id: user.id, active: true)
    unless membership && SupportDeskAccessPolicy.new(membership).allowed?(:ticket_read)
      return rejected
    end
    reset_session
    session[:auth_user_id] = user.id
    session[:auth_organization_id] = organization.id
    session[:locale] = organization.default_locale
    redirect_to root_path, status: :see_other
  end

  def destroy
    reset_session
    redirect_to password_sign_in_path, status: :see_other
  end

  private

  def rejected
    # Rate limiter is also active; errors don't distinguish users/tenants/passwords.
    flash.now[:alert] = t('auth.invalid_user')
    render :new, status: :unauthorized
  end

  def require_password_mode
    head :forbidden unless password_auth_mode?
  end
end
