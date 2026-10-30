# frozen_string_literal: true

# Tenant settings deliberately exclude policy_version, currency and vertical.
# These require explicit business-migration and editorial acceptance processes.
class OrganizationSettingsController < ApplicationController
  ALLOWED_TIMEZONES = %w[Asia/Ho_Chi_Minh UTC Asia/Singapore Europe/London America/New_York].freeze

  before_action -> { require_permission(:settings_read) }
  before_action -> { require_permission(:settings_manage) }, only: :update

  def show
    @organization = current_organization
  end

  def update
    org = current_organization
    input = params.require(:organization).permit(:name, :timezone, :default_locale)
    name = input[:name].to_s.strip
    timezone = input[:timezone].to_s
    locale = input[:default_locale].to_s
    unless name.length.between?(2, 120) && ALLOWED_TIMEZONES.include?(timezone) &&
        %w[vi en].include?(locale)
      return redirect_to organization_settings_path, alert: t('settings.invalid'), status: :see_other
    end

    ActiveRecord::Base.transaction do
      org.lock!
      before = {name: org.name, timezone: org.timezone, locale: org.default_locale}
      org.update!(name: name, timezone: timezone, default_locale: locale)
      audit!(action: 'organization.settings_changed', metadata: {
        before: before, after: {name: org.name, timezone: org.timezone, locale: org.default_locale}})
    end
    redirect_to organization_settings_path, notice: t('settings.saved'), status: :see_other
  end
end
