# frozen_string_literal: true
# Database/tenant assertions. Requires a running Rails 8 + PostgreSQL app with M1 migrations applied.
# Run: bin/rails runner script/verify_reference_fixtures.rb
class M1FixtureAssertionFailure < StandardError; end

def ensure_m1!(condition, message)
  raise M1FixtureAssertionFailure, message unless condition
  puts "PASS: #{message}"
end

tf = ActiveRecord::Base.connection.select_one(<<~SQL)
  SELECT i.status AS invoice_status, a.result AS activation_result, s.plan_code AS effective_plan,
         s.requested_plan_code AS requested_plan
  FROM tf_invoices i
  JOIN tf_subscriptions s ON s.organization_id = i.organization_id AND s.id = i.subscription_id
  JOIN tf_activation_events a ON a.organization_id = s.organization_id AND a.subscription_id = s.id AND a.invoice_id = i.id
  WHERE i.invoice_number = 'TF-INV-2026-0064'
SQL
ensure_m1!(tf && tf['invoice_status'] == 'paid' && tf['activation_result'] == 'failed' && tf['effective_plan'] == 'free' && tf['requested_plan'] == 'pro', 'TF paid invoice + failed activation keeps effective Free plan')

shipment = ActiveRecord::Base.connection.select_one(<<~SQL)
  SELECT o.status AS order_status, oi.quantity AS ordered_qty, SUM(si.shipped_quantity) AS shipped_qty,
    SUM(CASE WHEN sh.status = 'delivered' THEN si.shipped_quantity ELSE 0 END) AS delivered_qty,
    SUM(CASE WHEN sh.status = 'in_transit' THEN si.shipped_quantity ELSE 0 END) AS in_transit_qty,
    o.grand_total_vnd, o.shipping_vnd
  FROM nm_orders o
  JOIN nm_order_items oi ON oi.organization_id = o.organization_id AND oi.order_id = o.id
  JOIN nm_shipment_items si ON si.organization_id = oi.organization_id AND si.order_item_id = oi.id
  JOIN nm_shipments sh ON sh.organization_id = si.organization_id AND sh.id = si.shipment_id
  WHERE o.order_number = 'NM-2026-0042'
  GROUP BY o.status, oi.quantity, o.grand_total_vnd, o.shipping_vnd
SQL
ensure_m1!(shipment && shipment['order_status']=='shipped' && shipment['ordered_qty'].to_i == 2 && shipment['shipped_qty'].to_i == 2 && shipment['delivered_qty'].to_i == 1 && shipment['in_transit_qty'].to_i == 1, 'NM partial shipment remains 1 delivered and 1 in transit')
ensure_m1!(shipment['grand_total_vnd'].to_i == 640_000 && shipment['shipping_vnd'].to_i.zero?, 'NM immutable fixture totals are valid')

conn = ActiveRecord::Base.connection
org_a = conn.select_value("SELECT id FROM organizations WHERE slug = 'teamflow-cloud'")
org_b = conn.select_value("SELECT id FROM organizations WHERE slug = 'novamart-store'")
wrong_customer = conn.select_value("SELECT id FROM customers WHERE organization_id = #{Integer(org_b)} LIMIT 1")
ensure_m1!(org_a && org_b && wrong_customer, 'Both tenants and customer identities exist')

# Regression guard: cross-tenant customer linkage MUST fail at the DB FK layer.
# Uses a rollback-only savepoint to preserve data in both success/failure outcomes.
begin
  ActiveRecord::Base.transaction(requires_new: true) do
    conn.execute("INSERT INTO tickets (organization_id, customer_id, number, category, priority, status, created_at, updated_at) VALUES (#{Integer(org_a)}, #{Integer(wrong_customer)}, 'NEG-CROSS-TENANT', 'general_howto', 'P3', 'new', NOW(), NOW())")
    raise M1FixtureAssertionFailure, 'DB unexpectedly permitted a ticket linked to another tenant customer'
  end
rescue ActiveRecord::InvalidForeignKey, ActiveRecord::StatementInvalid => e
  ensure_m1!(e.message.match?(/foreign key|constraint/i), 'DB rejects a cross-tenant customer relation')
end
puts 'M1 reference fixture assertions passed (partial M1 coverage only).'
