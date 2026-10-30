# frozen_string_literal: true

# Platform-only tenant lifecycle. No tenant data browsing, deletion, policy edits,
# or automatic authorization of a newly created organization.
class PlatformOrganizationsController < PlatformBaseController
  TIMEZONES = OrganizationSettingsController::ALLOWED_TIMEZONES
  VERTICALS = %w[b2b_saas ecommerce].freeze

  def index
    @organizations = Organization.order(:slug).limit(100)
    @owners_by_org = Membership.includes(:user)
      .where(organization_id: @organizations.map(&:id), role: 'owner')
      .group_by(&:organization_id)
  end

  def new
    @organization = Organization.new(timezone: 'Asia/Ho_Chi_Minh', default_locale: 'vi')
  end

  def show
    @organization = Organization.find(params[:id])
    @owners = Membership.includes(:user).where(
      organization_id: @organization.id, role: 'owner').order(:id)
    @approved_kb_count = KnowledgeArticleVersion.where(
      organization_id: @organization.id, status: 'approved',
      policy_version: @organization.policy_version).count
  end

  def create
    input = params.require(:organization).permit(
      :slug, :name, :vertical, :currency, :timezone, :default_locale)
    attributes = normalized_attributes(input, creating: true)
    return redirect_to new_platform_organization_path, alert: t('platform_mgmt.invalid'),
      status: :see_other unless attributes

    ActiveRecord::Base.transaction do
      @organization = Organization.create!(attributes.merge(
        lifecycle_state: 'staging', policy_version: 'PENDING',
        lifecycle_changed_at: Time.current))
      platform_audit!(action: 'platform.organization.created_staging',
        organization: @organization, target: @organization,
        metadata: {to_state: 'staging'})
    end
    redirect_to platform_organization_path(@organization),
      notice: t('platform_mgmt.created_staging'), status: :see_other
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    redirect_to new_platform_organization_path,
      alert: t('platform_mgmt.invalid'), status: :see_other
  end

  def update
    org = Organization.find(params[:id])
    input = params.require(:organization).permit(:name, :timezone, :default_locale)
    attrs = normalized_attributes(input, creating: false)
    return redirect_to platform_organization_path(org),
      alert: t('platform_mgmt.invalid'), status: :see_other unless attrs

    ActiveRecord::Base.transaction do
      org.lock!
      changed = attrs.keys.select { |key| org.public_send(key) != attrs[key] }
      unless changed.empty?
        org.update!(attrs)
        platform_audit!(action: 'platform.organization.display_changed',
          organization: org, target: org, metadata: {changed_keys: changed})
      end
    end
    redirect_to platform_organization_path(org),
      notice: t('platform_mgmt.updated'), status: :see_other
  end

  def lifecycle
    org = Organization.find(params[:id])
    desired = params[:lifecycle_state].to_s
    return head :unprocessable_entity unless %w[active suspended].include?(desired)

    changed = false
    ActiveRecord::Base.transaction do
      org.lock!
      unless org.lifecycle_state == desired
        if desired == 'active'
          # Staged tenants have no validated M0 policy or evidence and cannot
          # become live simply by toggling a checkbox in Platform Console.
          return head :unprocessable_entity unless activation_ready?(org)
        end
        original = org.lifecycle_state
        org.update!(lifecycle_state: desired, lifecycle_changed_at: Time.current)
        platform_audit!(action: 'platform.organization.lifecycle_changed',
          organization: org, target: org,
          metadata: {from_state: original, to_state: desired})
        changed = true
      end
    end
    redirect_to platform_organization_path(org),
      notice: t(changed ? 'platform_mgmt.lifecycle_saved' : 'platform_mgmt.unchanged'),
      status: :see_other
  end

  private

  def normalized_attributes(input, creating:)
    name = input[:name].to_s.strip
    timezone = input[:timezone].to_s
    locale = input[:default_locale].to_s
    return nil unless name.length.between?(2, 120) &&
      TIMEZONES.include?(timezone) && %w[vi en].include?(locale)

    attributes = {name: name, timezone: timezone, default_locale: locale}
    return attributes unless creating
    slug = input[:slug].to_s.strip
    vertical = input[:vertical].to_s
    currency = input[:currency].to_s
    return nil unless slug.match?(/\A[a-z][a-z0-9-]{2,62}\z/) &&
      VERTICALS.include?(vertical) && %w[USD VND].include?(currency)
    attributes.merge(slug: slug, vertical: vertical, currency: currency)
  end

  def activation_ready?(org)
    return false if org.policy_version == 'PENDING'
    return false unless Membership.joins(:user)
      .where(organization_id: org.id, role: 'owner', active: true,
        users: {active: true}).exists?
    KnowledgeArticleVersion.where(organization_id: org.id,
      status: 'approved', policy_version: org.policy_version)
      .any?(&:active_on?)
  end
end
