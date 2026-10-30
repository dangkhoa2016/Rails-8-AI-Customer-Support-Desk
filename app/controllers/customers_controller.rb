class CustomersController < ApplicationController
  before_action -> { require_permission(:customer_manage) }, only: %i[new create edit update archive]
  def index
    @query = params[:q].to_s.strip.first(80)
    relation = Customer.where(organization_id: current_organization.id)
    @include_archived = can?(:customer_manage) && params[:include_archived] == '1'
    relation = relation.active unless @include_archived
    if @query.present?
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
      relation = relation.where('external_key ILIKE :query OR display_name ILIKE :query', query: pattern)
    end
    @filtered_count = relation.count
    @per_page = 20
    @total_pages = [(@filtered_count.to_f / @per_page).ceil, 1].max
    @page = params[:page].to_i.clamp(1, @total_pages)
    @customers = relation.order(:external_key).offset((@page - 1) * @per_page).limit(@per_page)
  end

  def new
    @customer = Customer.new(locale: current_organization.default_locale)
  end

  def create
    values = submitted_values(new_record: true)
    unless valid_customer_values?(values, new_record: true)
      return redirect_to new_customer_path, alert: t('customers.invalid_profile'), status: :see_other
    end
    ActiveRecord::Base.transaction do
      customer = Customer.create!(values.merge(organization_id: current_organization.id))
      audit!(action: 'customer.created', metadata: {customer_id: customer.id, external_key: customer.external_key})
      @customer = customer
    end
    redirect_to customer_path(@customer), notice: t('customers.created_profile'), status: :see_other
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    redirect_to new_customer_path, alert: t('customers.invalid_profile'), status: :see_other
  end

  def edit
    @customer = Customer.where(organization_id: current_organization.id).active.find(params[:id])
  end

  def update
    @customer = Customer.where(organization_id: current_organization.id).active.find(params[:id])
    values = submitted_values(new_record: false)
    unless valid_customer_values?(values, new_record: false)
      return redirect_to edit_customer_path(@customer), alert: t('customers.invalid_profile'), status: :see_other
    end
    ActiveRecord::Base.transaction do
      @customer.update!(values)
      audit!(action: 'customer.profile_updated', metadata: {customer_id: @customer.id})
    end
    redirect_to customer_path(@customer), notice: t('customers.updated_profile'), status: :see_other
  end

  def archive
    @customer = Customer.where(organization_id: current_organization.id).active.find(params[:id])
    ActiveRecord::Base.transaction do
      @customer.update!(archived_at: Time.current)
      audit!(action: 'customer.archived', metadata: {customer_id: @customer.id})
    end
    redirect_to customers_path, notice: t('customers.archived_profile'), status: :see_other
  end

  def show
    @customer = Customer.where(organization_id: current_organization.id).find(params[:id])
    @tickets = scoped_tickets.where(customer_id: @customer.id).order(created_at: :desc).limit(20)
    if current_organization.vertical == 'b2b_saas'
      workspace = TfWorkspace.find_by(organization_id: current_organization.id, customer_id: @customer.id)
      @references = workspace ? TfInvoice.where(organization_id: current_organization.id, workspace_id: workspace.id).order(:invoice_number).limit(20) : []
    else
      @references = NmOrder.where(organization_id: current_organization.id, customer_id: @customer.id).order(:order_number).limit(20)
    end
  end
  private

  def submitted_values(new_record:)
    permitted = params.require(:customer).permit(
      :external_key, :display_name, :locale, :synthetic_email, :company_name, :contact_phone)
    values = permitted.to_h.transform_values { |value| value.to_s.strip }
    values.delete('external_key') unless new_record
    values
  end

  def valid_customer_values?(values, new_record:)
    return false if new_record && !values['external_key'].to_s.match?(/\A[A-Za-z0-9][A-Za-z0-9_-]{2,63}\z/)
    return false unless values['display_name'].to_s.length.between?(2, 120)
    return false unless %w[vi en].include?(values['locale'])
    return false unless values['synthetic_email'].to_s.match?(/\A[^\s@]+@(?:[a-z0-9-]+\.)?example\.test\z/i) &&
      values['synthetic_email'].length <= 254
    return false if values['company_name'].to_s.length > 120
    return false unless values['contact_phone'].to_s.match?(/\A[+0-9() .-]{0,24}\z/)
    true
  end
end
