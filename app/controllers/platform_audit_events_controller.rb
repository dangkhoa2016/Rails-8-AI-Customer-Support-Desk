# frozen_string_literal: true

# Platform audit view contains only controlled metadata; no tenant conversations.
class PlatformAuditEventsController < PlatformBaseController
  PER_PAGE = 25
  ACTIONS = %w[
    platform.organization.created_staging
    platform.organization.display_changed
    platform.organization.lifecycle_changed
    platform.owner.provisioned_inactive
    platform.owner.active_changed
  ].freeze

  def index
    @action_filter = params[:action_filter].to_s
    @organization_filter = params[:organization_id].to_s
    @page = [params[:page].to_i, 1].max
    @page = @page.clamp(1, 10_000)
    @organizations = Organization.order(:slug).limit(100)

    scope = PlatformAuditEvent.includes(:platform_admin, :organization)
    scope = scope.where(action: @action_filter) if ACTIONS.include?(@action_filter)
    if @organization_filter.match?(/\A[1-9]\d{0,18}\z/)
      scope = scope.where(organization_id: @organization_filter.to_i)
    end
    @total = scope.count
    @events = scope.order(created_at: :desc, id: :desc)
      .limit(PER_PAGE).offset((@page - 1) * PER_PAGE)
  end
end
