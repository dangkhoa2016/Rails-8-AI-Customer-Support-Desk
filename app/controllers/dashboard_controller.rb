class DashboardController < ApplicationController
  def index
    @ticket_counts = scoped_tickets.group(:status).count
    @recent_tickets = scoped_tickets.order(created_at: :desc).limit(8)
    @customer_count = Customer.where(organization_id: current_organization.id).count
    @business_counts = if current_organization.vertical == 'b2b_saas'
      {first: TfWorkspace.where(organization_id: current_organization.id).count,
       second: TfInvoice.where(organization_id: current_organization.id).count,
       third: TfExportJob.where(organization_id: current_organization.id).count}
    else
      {first: NmOrder.where(organization_id: current_organization.id).count,
       second: NmShipment.where(organization_id: current_organization.id).count,
       third: NmReturnRequest.where(organization_id: current_organization.id).count}
    end
  end
end
