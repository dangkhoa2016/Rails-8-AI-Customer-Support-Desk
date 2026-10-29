class BusinessRecordsController < ApplicationController
  before_action :require_writer

  def teamflow_invoice
    @business_type = 'teamflow'
    @evidence = lookup.teamflow_invoice(customer_key: params.require(:customer_key), invoice_number: params.require(:invoice_number))
    render :show
  rescue SupportDesk::ReadOnlyBusinessLookup::NotFound
    head :not_found
  end

  def novamart_order
    @business_type = 'novamart'
    @evidence = lookup.novamart_order(customer_key: params.require(:customer_key), order_number: params.require(:order_number))
    render :show
  rescue SupportDesk::ReadOnlyBusinessLookup::NotFound
    head :not_found
  end

  private

  def lookup
    @lookup ||= SupportDesk::ReadOnlyBusinessLookup.new(authenticated_user: current_user, organization: current_organization)
  end
end
