class CustomersController < ApplicationController
  def index
    @customers = Customer.where(organization_id: current_organization.id).order(:external_key).limit(120)
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
