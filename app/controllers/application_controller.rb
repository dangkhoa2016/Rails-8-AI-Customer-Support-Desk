# This is a deliberately DEVELOPMENT-ONLY synthetic demo sign-in, NOT production auth.
# Every lookup is derived from a validated membership/session (never LLM or tenant params).
class ApplicationController < ActionController::Base
  before_action :set_locale
  before_action :require_demo_session
  helper_method :current_user, :current_organization, :current_membership, :can_write?, :can?, :access_policy, :password_auth_mode?

  private

  def demo_enabled?
    Rails.env.development? || Rails.env.test?
  end

  def password_auth_mode?
    (Rails.env.production? && ENV['P0_PASSWORD_AUTH_ENABLE'] == 'YES') ||
      (Rails.env.test? && ENV['P0_PASSWORD_AUTH_TEST_MODE'] == 'YES')
  end

  def require_demo_session
    unless demo_enabled? || password_auth_mode?
      render plain: 'Authentication unavailable. Contact the system administrator.', status: :forbidden
      return
    end
    return if current_membership

    reset_session
    redirect_to (password_auth_mode? ? password_sign_in_path : demo_sign_in_path),
      alert: t('auth.login_required')
  end

  def current_membership
    return @current_membership if defined?(@current_membership)
    user_id = session[password_auth_mode? ? :auth_user_id : :demo_user_id]
    tenant_id = session[password_auth_mode? ? :auth_organization_id : :demo_organization_id]
    @current_membership = if user_id.present? && tenant_id.present?
      member = Membership.includes(:organization, :user).find_by(user_id: user_id, organization_id: tenant_id)
      member if member && SupportDeskAccessPolicy.new(member).allowed?(:ticket_read)
    end
  end

  def current_organization
    current_membership&.organization
  end

  def current_user
    return nil unless current_membership
    @current_user ||= User.find_by(id: current_membership.user_id)
  end

  def access_policy
    @access_policy ||= SupportDeskAccessPolicy.new(current_membership)
  end

  def can?(permission)
    access_policy.allowed?(permission)
  end

  def can_write?
    can?(:ticket_update)
  end

  def require_permission(permission)
    head :forbidden unless can?(permission)
  end

  def require_writer
    require_permission(:ticket_update)
  end

  def scoped_tickets
    Ticket.where(organization_id: current_organization.id)
  end

  def set_locale
    if %w[vi en].include?(params[:locale])
      session[:locale] = params[:locale]
    end
    I18n.locale = session[:locale].presence_in(%w[vi en]) || I18n.default_locale
  end

  def audit!(action:, ticket: nil, metadata: {})
    AuditEvent.create!(organization_id: current_organization.id, actor_user_id: current_user.id,
                       ticket_id: ticket&.id, action: action, metadata: metadata)
  end
end
