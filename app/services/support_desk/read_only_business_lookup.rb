# frozen_string_literal: true
# M1 read-only business lookup used by Rails agent controllers (not a public endpoint).
# The organization and authenticated_user MUST come from a trusted authenticated Rails context.
# Do not instantiate with LLM-supplied account/tenant identifiers.
module SupportDesk
  class ReadOnlyBusinessLookup
    class AccessDenied < StandardError; end
    class NotFound < StandardError; end

    def initialize(authenticated_user:, organization:)
      raise AccessDenied, 'missing trusted user or tenant' unless authenticated_user.is_a?(User) && organization.is_a?(Organization)
      @organization = organization
      @membership = Membership.where(organization_id: organization.id, user_id: authenticated_user.id).first
      raise AccessDenied, 'support membership required' unless @membership && %w[owner admin agent].include?(@membership.role)
    end

    # Nothing from another tenant may be looked up, even when an invoice number happens to match.
    # A customer key is mandatory: an agent lookup must resolve the correct customer workspace.
    def teamflow_invoice(customer_key:, invoice_number:)
      raise NotFound unless @organization.vertical == 'b2b_saas'
      customer = Customer.where(organization_id: @organization.id, external_key: customer_key).first
      raise NotFound unless customer
      workspace = TfWorkspace.where(organization_id: @organization.id, customer_id: customer.id).first
      raise NotFound unless workspace
      invoice = TfInvoice.where(organization_id: @organization.id, workspace_id: workspace.id, invoice_number: invoice_number).first
      raise NotFound unless invoice
      sub = TfSubscription.where(organization_id: @organization.id, id: invoice.subscription_id, workspace_id: workspace.id).first
      raise NotFound unless sub
      activation = TfActivationEvent.where(organization_id: @organization.id, invoice_id: invoice.id, subscription_id: sub.id).order(occurred_at: :desc, id: :desc).first
      {
        invoice_number: invoice.invoice_number,
        invoice_status: invoice.status,
        paid_at: invoice.paid_at&.iso8601,
        amount_cents: invoice.total_cents,
        effective_plan: sub.plan_code,
        requested_plan: sub.requested_plan_code,
        subscription_status: sub.status,
        activation_result: activation&.result,
        activation_confirmed: invoice.status == 'paid' && activation&.result == 'succeeded',
        evidence_ids: [invoice.invoice_number, workspace.workspace_key]
      }
    end

    def novamart_order(customer_key:, order_number:)
      raise NotFound unless @organization.vertical == 'ecommerce'
      customer = Customer.where(organization_id: @organization.id, external_key: customer_key).first
      raise NotFound unless customer
      order = NmOrder.where(organization_id: @organization.id, customer_id: customer.id, order_number: order_number).first
      raise NotFound unless order
      items = NmOrderItem.where(organization_id: @organization.id, order_id: order.id).order(:id).to_a
      payments = NmPayment.where(organization_id: @organization.id, order_id: order.id).order(:id).to_a
      shipments = NmShipment.where(organization_id: @organization.id, order_id: order.id).order(:id).to_a
      ship_items = NmShipmentItem.where(organization_id: @organization.id, order_id: order.id).to_a
      shipment_by_id = shipments.index_by(&:id)
      amounts = items.map do |item|
        matching = ship_items.select { |si| si.order_item_id == item.id }
        {
          sku: item.sku_snapshot, ordered: item.quantity,
          shipped: matching.sum(&:shipped_quantity),
          delivered: matching.sum { |si| shipment_by_id.fetch(si.shipment_id).status == 'delivered' ? si.shipped_quantity : 0 }
        }
      end
      {
        order_number: order.order_number, order_status: order.status,
        grand_total_vnd: order.grand_total_vnd, shipping_vnd: order.shipping_vnd,
        payment_status: payments.first&.status,
        items: amounts,
        shipments: shipments.map { |s| {reference: s.shipment_key, status: s.status, delivered_at: s.delivered_at&.iso8601} },
        fully_delivered: amounts.all? { |i| i[:ordered] == i[:delivered] },
        evidence_ids: [order.order_number] + shipments.map(&:shipment_key)
      }
    end
  end
end
