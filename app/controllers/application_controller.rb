# This is a deliberately DEVELOPMENT-ONLY synthetic demo sign-in, NOT production auth.
# Every lookup is derived from a validated membership/session (never LLM or tenant params).
class ApplicationController < ActionController::Base
  before_action :set_locale
  before_action :require_demo_session
  helper_method :current_user, :current_organization, :current_membership, :can_write?

  private

  def demo_enabled?
    Rails.env.development? || Rails.env.test?
  end

  def require_demo_session
    unless demo_enabled?
      render plain: 'Synthetic demo login disabled outside development/test.', status: :forbidden
      return
    end
    return if current_membership

    reset_session
    redirect_to demo_sign_in_path, alert: t('auth.login_required')
  end

  def current_membership
    return @current_membership if defined?(@current_membership)
    user_id = session[:demo_user_id]
    tenant_id = session[:demo_organization_id]
    @current_membership = if user_id.present? && tenant_id.present?
      Membership.includes(:organization).find_by(user_id: user_id, organization_id: tenant_id)
    end
  end

  def current_organization
    current_membership&.organization
  end

  def current_user
    return nil unless current_membership
    @current_user ||= User.find_by(id: current_membership.user_id)
  end

  def can_write?
    current_membership && %w[owner admin agent].include?(current_membership.role)
  end

  def require_writer
    head :forbidden unless can_write?
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
