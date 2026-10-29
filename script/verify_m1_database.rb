# frozen_string_literal: true
# Requires Rails 8, PostgreSQL, migrated/seeded synthetic database.
# Stronger than the offline JSON verifier but not a production security audit.
require 'json'
require 'digest'
require 'time'
require_relative '../app/services/support_desk/read_only_business_lookup'

class M1DatabaseVerificationFailure < StandardError; end

def ensure_m1(condition, message)
  raise M1DatabaseVerificationFailure, message unless condition
  puts "PASS: #{message}"
end

source = Rails.root.join('data/m1_business_records.json')
manifest = Rails.root.join('data/m1_business_records.manifest.json')
raise 'source/manifest missing' unless File.exist?(source) && File.exist?(manifest)
data = JSON.parse(File.read(source))
raise 'dataset checksum mismatch' unless Digest::SHA256.file(source).hexdigest == JSON.parse(File.read(manifest)).fetch('dataset_sha256')
ensure_m1(ActiveRecord::Base.connection.adapter_name == 'PostgreSQL', 'PostgreSQL adapter in use')
conn = ActiveRecord::Base.connection
counts = data.fetch('records').transform_values do |rows|
  raise M1DatabaseVerificationFailure, 'Empty table record list' if rows.empty?
  rows.length
end
counts.each do |table, expected|
  actual = conn.select_value("SELECT COUNT(*) FROM #{conn.quote_table_name(table)}").to_i
  ensure_m1(actual == expected, "#{table} row count #{actual}/#{expected}")
end

require_relative './verify_reference_fixtures'
tf_agent = User.find_by!(email: 'tf-agent@example.test')
nm_agent = User.find_by!(email: 'nm-agent@example.test')
tf_org = Organization.find_by!(slug: 'teamflow-cloud')
nm_org = Organization.find_by!(slug: 'novamart-store')

service = SupportDesk::ReadOnlyBusinessLookup.new(authenticated_user: tf_agent, organization: tf_org)
tf = service.teamflow_invoice(customer_key: 'TF-C-014', invoice_number: 'TF-INV-2026-0064')
ensure_m1(tf[:invoice_status] == 'paid' && tf[:activation_result] == 'failed' && !tf[:activation_confirmed] && tf[:effective_plan] == 'free', 'authorized TF lookup never asserts false activation')

begin
  SupportDesk::ReadOnlyBusinessLookup.new(authenticated_user: tf_agent, organization: nm_org)
  raise M1DatabaseVerificationFailure, 'cross-tenant agent unexpectedly authorized'
rescue SupportDesk::ReadOnlyBusinessLookup::AccessDenied
  puts 'PASS: TF agent is denied NovaMart records'
end
begin
  service.teamflow_invoice(customer_key: 'TF-C-001', invoice_number: 'TF-INV-2026-0064')
  raise M1DatabaseVerificationFailure, 'wrong customer invoice unexpectedly visible'
rescue SupportDesk::ReadOnlyBusinessLookup::NotFound
  puts 'PASS: same-tenant different-customer invoice denied'
end
viewer = User.find_by!(email: 'tf-viewer@example.test')
begin
  SupportDesk::ReadOnlyBusinessLookup.new(authenticated_user: viewer, organization: tf_org)
  raise M1DatabaseVerificationFailure, 'viewer unexpectedly authorized to agent read-only tool'
rescue SupportDesk::ReadOnlyBusinessLookup::AccessDenied
  puts 'PASS: viewer denied agent-only business tool'
end
nova = SupportDesk::ReadOnlyBusinessLookup.new(authenticated_user: nm_agent, organization: nm_org)
order = nova.novamart_order(customer_key: 'NM-C-031', order_number: 'NM-2026-0042')
ensure_m1(order[:order_status] == 'shipped' && !order[:fully_delivered] && order[:payment_status] == 'paid' && order[:grand_total_vnd] == 640_000, 'authorized NM partial shipment lookup grounded')
ensure_m1(order[:items] == [{sku: 'NM-KBD-011', ordered: 2, shipped: 2, delivered: 1}], 'NM 1 delivered and 1 still in transit')

# Detect money inconsistencies and quantity overships from imported DB rows rather than just JSON.
wrong_amounts = conn.select_value(<<~SQL).to_i
  SELECT COUNT(*) FROM nm_orders o
  LEFT JOIN (
     SELECT organization_id, order_id, SUM(quantity * unit_price_snapshot_vnd) AS subtotal,
            SUM(discount_snapshot_vnd) AS discount
     FROM nm_order_items GROUP BY organization_id, order_id
  ) sums ON sums.organization_id = o.organization_id AND sums.order_id = o.id
  WHERE sums.subtotal IS NULL OR o.subtotal_vnd <> sums.subtotal OR o.discount_vnd <> sums.discount OR
        o.grand_total_vnd <> sums.subtotal - sums.discount + o.shipping_vnd OR
        o.shipping_vnd <> CASE WHEN sums.subtotal - sums.discount >= 500000 THEN 0 ELSE 30000 END
SQL
ensure_m1(wrong_amounts.zero?, 'DB order snapshots match all totals and shipping rules')
overship = conn.select_value(<<~SQL).to_i
  SELECT COUNT(*) FROM nm_order_items oi
  LEFT JOIN (SELECT organization_id, order_item_id, SUM(shipped_quantity) AS shipped
    FROM nm_shipment_items GROUP BY organization_id, order_item_id) si
    ON si.organization_id = oi.organization_id AND si.order_item_id = oi.id
  WHERE COALESCE(si.shipped, 0) > oi.quantity
SQL
ensure_m1(overship.zero?, 'DB has no overshipped order items')

puts JSON.pretty_generate({status: 'PASS_POSTGRESQL_M1_PARTIAL_ACCEPTANCE', dataset_sha256: Digest::SHA256.file(source).hexdigest,
  counts: counts, checks: %w[reference_fixtures composite_foreign_key authz_customer_scope money_snapshots overship_scan]})
