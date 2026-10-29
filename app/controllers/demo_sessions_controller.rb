class DemoSessionsController < ApplicationController
  skip_before_action :require_demo_session
  before_action :require_dev_mode

  def new
    @memberships = Membership.includes(:user, :organization).order(:organization_id, :role)
  end

  def create
    membership = Membership.find_by(id: params[:membership_id])
    if membership.nil?
      redirect_to demo_sign_in_path, alert: t('auth.invalid_user')
      return
    end
    reset_session
    session[:demo_user_id] = membership.user_id
    session[:demo_organization_id] = membership.organization_id
    session[:locale] = params[:locale] == 'en' ? 'en' : 'vi'
    redirect_to root_path, notice: t('auth.signed_in')
  end

  def destroy
    reset_session
    redirect_to demo_sign_in_path, notice: t('auth.signed_out')
  end

  private

  def require_dev_mode
    head :forbidden unless demo_enabled?
  end
end
