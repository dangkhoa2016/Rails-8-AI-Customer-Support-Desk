class CustomersController < ApplicationController
  def index
    @query = params[:q].to_s.strip.first(80)
    relation = Customer.where(organization_id: current_organization.id)
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
end
