# frozen_string_literal: true
# Deterministic reference fixtures only. NOT the full M1 business-record dataset.
# Run inside a Rails 8 app after migrations: bin/rails runner db/seeds/m1_reference_fixtures.rb
require 'time'

seed_model = ->(table) { Class.new(ActiveRecord::Base) { self.table_name = table } }
Organization = seed_model.call('organizations') unless defined?(Organization)
Customer = seed_model.call('customers') unless defined?(Customer)
TfWorkspace = seed_model.call('tf_workspaces') unless defined?(TfWorkspace)
TfSubscription = seed_model.call('tf_subscriptions') unless defined?(TfSubscription)
TfInvoice = seed_model.call('tf_invoices') unless defined?(TfInvoice)
TfActivationEvent = seed_model.call('tf_activation_events') unless defined?(TfActivationEvent)
NmProduct = seed_model.call('nm_products') unless defined?(NmProduct)
NmOrder = seed_model.call('nm_orders') unless defined?(NmOrder)
NmOrderItem = seed_model.call('nm_order_items') unless defined?(NmOrderItem)
NmPayment = seed_model.call('nm_payments') unless defined?(NmPayment)
NmShipment = seed_model.call('nm_shipments') unless defined?(NmShipment)
NmShipmentItem = seed_model.call('nm_shipment_items') unless defined?(NmShipmentItem)

upsert_fixture = lambda do |model, key, attributes|
  record = model.find_or_initialize_by(key)
  record.assign_attributes(attributes)
  record.save!
  record
end

timestamp = ->(iso) { Time.iso8601(iso).utc }

ActiveRecord::Base.transaction do
  tf_org = upsert_fixture.call(Organization, {slug: 'teamflow-cloud'}, {name: 'TeamFlow Cloud', vertical: 'b2b_saas', currency: 'USD', timezone: 'Asia/Ho_Chi_Minh', default_locale: 'vi', policy_version: '1.0.0'})
  nm_org = upsert_fixture.call(Organization, {slug: 'novamart-store'}, {name: 'NovaMart Store', vertical: 'ecommerce', currency: 'VND', timezone: 'Asia/Ho_Chi_Minh', default_locale: 'vi', policy_version: '1.0.0'})
  tf_customer = upsert_fixture.call(Customer, {organization_id: tf_org.id, external_key: 'TF-C-014'}, {synthetic_email: 'tf-c-014@example.test', locale: 'en', display_name: 'Synthetic TF Customer 014'})
  nm_customer = upsert_fixture.call(Customer, {organization_id: nm_org.id, external_key: 'NM-C-031'}, {synthetic_email: 'nm-c-031@example.test', locale: 'vi', display_name: 'Synthetic NM Customer 031'})

  workspace = upsert_fixture.call(TfWorkspace, {organization_id: tf_org.id, workspace_key: 'TF-WS-014'}, {customer_id: tf_customer.id})
  subscription = upsert_fixture.call(TfSubscription, {organization_id: tf_org.id, workspace_id: workspace.id}, {
    plan_code: 'free', requested_plan_code: 'pro', status: 'free', effective_at: timestamp.call('2026-10-01T09:00:00+07:00')
  })
  invoice = upsert_fixture.call(TfInvoice, {organization_id: tf_org.id, invoice_number: 'TF-INV-2026-0064'}, {
    workspace_id: workspace.id, subscription_id: subscription.id, total_cents: 6900, status: 'paid', paid_at: timestamp.call('2026-10-25T10:00:00+07:00')
  })
  upsert_fixture.call(TfActivationEvent, {organization_id: tf_org.id, subscription_id: subscription.id, invoice_id: invoice.id, result: 'failed'}, {
    occurred_at: timestamp.call('2026-10-25T10:01:00+07:00'), activated_at: nil
  })

  upsert_fixture.call(NmProduct, {organization_id: nm_org.id, sku: 'NM-KBD-011'}, {
    name: 'Synthetic keyboard', current_price_vnd: 320_000, stock: 100, warranty_months: 12, active: true
  })
  order = upsert_fixture.call(NmOrder, {organization_id: nm_org.id, order_number: 'NM-2026-0042'}, {
    customer_id: nm_customer.id, status: 'shipped', subtotal_vnd: 640_000, discount_vnd: 0, shipping_vnd: 0, grand_total_vnd: 640_000
  })
  item = upsert_fixture.call(NmOrderItem, {organization_id: nm_org.id, order_id: order.id, sku_snapshot: 'NM-KBD-011'}, {
    unit_price_snapshot_vnd: 320_000, quantity: 2, discount_snapshot_vnd: 0
  })
  upsert_fixture.call(NmPayment, {organization_id: nm_org.id, payment_key: 'NM-PAY-2026-0042'}, {
    order_id: order.id, amount_vnd: 640_000, status: 'paid', confirmed_at: timestamp.call('2026-10-25T09:00:00+07:00')
  })
  shipment_a = upsert_fixture.call(NmShipment, {organization_id: nm_org.id, shipment_key: 'NM-SHIP-042-A'}, {
    order_id: order.id, carrier_label: 'SYNTHETIC-CARRIER-A', status: 'delivered', shipped_at: timestamp.call('2026-10-26T09:00:00+07:00'), delivered_at: timestamp.call('2026-10-27T09:00:00+07:00')
  })
  shipment_b = upsert_fixture.call(NmShipment, {organization_id: nm_org.id, shipment_key: 'NM-SHIP-042-B'}, {
    order_id: order.id, carrier_label: 'SYNTHETIC-CARRIER-B', status: 'in_transit', shipped_at: timestamp.call('2026-10-26T11:00:00+07:00'), delivered_at: nil
  })
  upsert_fixture.call(NmShipmentItem, {organization_id: nm_org.id, shipment_id: shipment_a.id, order_item_id: item.id}, {order_id: order.id, shipped_quantity: 1})
  upsert_fixture.call(NmShipmentItem, {organization_id: nm_org.id, shipment_id: shipment_b.id, order_item_id: item.id}, {order_id: order.id, shipped_quantity: 1})
end
puts 'Seeded 2 organizations and 2 reference fixtures (NOT full M1 targets).'
