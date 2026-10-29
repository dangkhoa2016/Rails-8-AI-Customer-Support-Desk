# frozen_string_literal: true
# Rails runner: db/seeds/m1_full_business_records.rb
# Performs STRICT, idempotent, transactional import of offline-generated synthetic M1 data.
# Does not seed tickets, KB, evaluation gold or any AI output. Requires PostgreSQL migrations.
require 'digest'
require 'json'
require 'time'
require Rails.root.join('script/m1_seed_timestamp').to_s

namespace = Module.new
records_model = lambda do |table|
  klass = Class.new(ActiveRecord::Base)
  klass.table_name = table
  klass.inheritance_column = :_disabled_sti
  klass
end
models = {}
%w[organizations users memberships customers tf_workspaces tf_subscriptions tf_invoices tf_activation_events
   tf_export_jobs tf_api_request_events tf_service_incidents nm_products nm_orders nm_order_items
   nm_payments nm_shipments nm_shipment_items nm_return_requests nm_return_items nm_warranty_claims].each do |table|
  models[table] = records_model.call(table)
end
root = Rails.root
source_file = root.join('data', 'm1_business_records.json')
manifest_file = root.join('data', 'm1_business_records.manifest.json')
raise "Missing #{source_file}" unless File.file?(source_file)
raise "Missing #{manifest_file}" unless File.file?(manifest_file)
json = JSON.parse(File.read(source_file))
manifest = JSON.parse(File.read(manifest_file))
actual_sha = Digest::SHA256.file(source_file).hexdigest
raise 'Dataset SHA256 does not match its manifest' unless actual_sha == manifest.fetch('dataset_sha256')
raise 'Unapproved policy version' unless json.fetch('policy_version') == '1.0.0' && json.fetch('seed') == 20_261_028
raise 'Wrong dataset kind' unless json.fetch('kind') == 'M1_DETERMINISTIC_BUSINESS_RECORDS_ONLY'
raise 'Require PostgreSQL' unless ActiveRecord::Base.connection.adapter_name == 'PostgreSQL'
rows = json.fetch('records')
expected_keys = models.keys.sort
raise 'Unexpected/missing tables in the dataset' unless rows.keys.sort == expected_keys

# Supports only synthetic NEW demo DBs; avoid ever writing to real customer tables.
if ENV['M1_SYNTHETIC_DEMO'] != 'YES'
  abort 'Refusing to seed until M1_SYNTHETIC_DEMO=YES is set explicitly.'
end

upsert = lambda do |table, identity, attrs|
  object = models.fetch(table).find_or_initialize_by(identity)
  object.assign_attributes(attrs)
  fixed = Time.iso8601(json.fetch('reference_time'))
  # Business rows are historical snapshots. Never stamp all created_at values at
  # the reference time (which would put payments/shipments before order creation).
  object.created_at ||= SupportDesk::M1SeedTimestamp.timestamp_for(
    table, attrs, reference_time: json.fetch('reference_time')
  ) if object.has_attribute?(:created_at)
  object.updated_at = fixed if object.has_attribute?(:updated_at)
  object.save!
  object
end
orgs = {}
user_ids = {}
customer_ids = {}
workspace_ids = {}
subscriptions = {}
invoice_ids = {}
order_ids = {}
order_item_ids = {}
shipment_ids = {}
return_ids = {}

ActiveRecord::Base.transaction do
  rows.fetch('organizations').each do |r|
    attrs = r.reject { |k, _| k == 'slug' }
    o = upsert.call('organizations', {slug: r.fetch('slug')}, attrs)
    orgs[r.fetch('slug')] = o.id
  end
  rows.fetch('users').each do |r|
    u = upsert.call('users', {email: r.fetch('email')}, {display_name: r.fetch('display_name')})
    user_ids[r.fetch('email')] = u.id
  end
  rows.fetch('memberships').each do |r|
    upsert.call('memberships', {organization_id: orgs.fetch(r.fetch('organization')), user_id: user_ids.fetch(r.fetch('email'))},
      {role: r.fetch('role')})
  end
  rows.fetch('customers').each do |r|
    org = orgs.fetch(r.fetch('organization'))
    attrs = r.reject { |k, _| %w[organization external_key].include?(k) }
    c = upsert.call('customers', {organization_id: org, external_key: r.fetch('external_key')}, attrs)
    customer_ids[[r.fetch('organization'), r.fetch('external_key')]] = c.id
  end
  rows.fetch('tf_workspaces').each do |r|
    org = orgs.fetch(r.fetch('organization'))
    w = upsert.call('tf_workspaces', {organization_id: org, workspace_key: r.fetch('workspace_key')},
      {customer_id: customer_ids.fetch([r.fetch('organization'), r.fetch('customer_key')])})
    workspace_ids[[r.fetch('organization'), r.fetch('workspace_key')]] = w.id
  end
  rows.fetch('tf_subscriptions').each do |r|
    org = orgs.fetch(r.fetch('organization'))
    w = workspace_ids.fetch([r.fetch('organization'), r.fetch('workspace_key')])
    attrs = r.reject { |k, _| %w[organization workspace_key].include?(k) }
    s = upsert.call('tf_subscriptions', {organization_id: org, workspace_id: w}, attrs)
    subscriptions[[r.fetch('organization'), r.fetch('workspace_key')]] = s.id
  end
  rows.fetch('tf_invoices').each do |r|
    orgkey = r.fetch('organization')
    attrs = r.reject { |k, _| %w[organization workspace_key invoice_number].include?(k) }
    attrs[:workspace_id] = workspace_ids.fetch([orgkey, r.fetch('workspace_key')])
    attrs[:subscription_id] = subscriptions.fetch([orgkey, r.fetch('workspace_key')])
    inv = upsert.call('tf_invoices', {organization_id: orgs.fetch(orgkey), invoice_number: r.fetch('invoice_number')}, attrs)
    invoice_ids[[orgkey, r.fetch('invoice_number')]] = inv.id
  end
  rows.fetch('tf_activation_events').each do |r|
    orgkey = r.fetch('organization')
    upsert.call('tf_activation_events', {
      organization_id: orgs.fetch(orgkey),
      subscription_id: subscriptions.fetch([orgkey, r.fetch('workspace_key')]),
      invoice_id: invoice_ids.fetch([orgkey, r.fetch('invoice_number')]),
      result: r.fetch('result')
    }, {occurred_at: r.fetch('occurred_at'), activated_at: r['activated_at']})
  end
  rows.fetch('tf_export_jobs').each do |r|
    orgkey = r.fetch('organization')
    attrs = r.reject { |k, _| %w[organization workspace_key job_key].include?(k) }
    attrs[:workspace_id] = workspace_ids.fetch([orgkey, r.fetch('workspace_key')])
    upsert.call('tf_export_jobs', {organization_id: orgs.fetch(orgkey), job_key: r.fetch('job_key')}, attrs)
  end
  rows.fetch('tf_api_request_events').each do |r|
    orgkey = r.fetch('organization')
    attrs = r.reject { |k, _| %w[organization workspace_key request_id].include?(k) }
    attrs[:workspace_id] = workspace_ids.fetch([orgkey, r.fetch('workspace_key')])
    upsert.call('tf_api_request_events', {organization_id: orgs.fetch(orgkey), request_id: r.fetch('request_id')}, attrs)
  end
  rows.fetch('tf_service_incidents').each do |r|
    orgkey = r.fetch('organization')
    attrs = r.reject { |k, _| %w[organization incident_key].include?(k) }
    upsert.call('tf_service_incidents', {organization_id: orgs.fetch(orgkey), incident_key: r.fetch('incident_key')}, attrs)
  end
  rows.fetch('nm_products').each do |r|
    orgkey = r.fetch('organization')
    attrs = r.reject { |k, _| %w[organization sku].include?(k) }
    upsert.call('nm_products', {organization_id: orgs.fetch(orgkey), sku: r.fetch('sku')}, attrs)
  end
  rows.fetch('nm_orders').each do |r|
    orgkey = r.fetch('organization')
    attrs = r.reject { |k, _| %w[organization order_number customer_key].include?(k) }
    attrs[:customer_id] = customer_ids.fetch([orgkey, r.fetch('customer_key')])
    o = upsert.call('nm_orders', {organization_id: orgs.fetch(orgkey), order_number: r.fetch('order_number')}, attrs)
    order_ids[[orgkey, r.fetch('order_number')]] = o.id
  end
  rows.fetch('nm_order_items').each do |r|
    orgkey = r.fetch('organization')
    order_id = order_ids.fetch([orgkey, r.fetch('order_number')])
    attrs = r.reject { |k, _| %w[organization order_number sku_snapshot].include?(k) }
    item = upsert.call('nm_order_items', {
      organization_id: orgs.fetch(orgkey), order_id: order_id, sku_snapshot: r.fetch('sku_snapshot')
    }, attrs)
    order_item_ids[[orgkey, r.fetch('order_number'), r.fetch('sku_snapshot')]] = item.id
  end
  rows.fetch('nm_payments').each do |r|
    orgkey = r.fetch('organization')
    attrs = r.reject { |k, _| %w[organization order_number payment_key].include?(k) }
    attrs[:order_id] = order_ids.fetch([orgkey, r.fetch('order_number')])
    upsert.call('nm_payments', {organization_id: orgs.fetch(orgkey), payment_key: r.fetch('payment_key')}, attrs)
  end
  rows.fetch('nm_shipments').each do |r|
    orgkey = r.fetch('organization')
    attrs = r.reject { |k, _| %w[organization order_number shipment_key].include?(k) }
    attrs[:order_id] = order_ids.fetch([orgkey, r.fetch('order_number')])
    s = upsert.call('nm_shipments', {organization_id: orgs.fetch(orgkey), shipment_key: r.fetch('shipment_key')}, attrs)
    shipment_ids[[orgkey, r.fetch('shipment_key')]] = s.id
  end
  rows.fetch('nm_shipment_items').each do |r|
    orgkey = r.fetch('organization')
    upsert.call('nm_shipment_items', {
      organization_id: orgs.fetch(orgkey),
      shipment_id: shipment_ids.fetch([orgkey, r.fetch('shipment_key')]),
      order_item_id: order_item_ids.fetch([orgkey, r.fetch('order_number'), r.fetch('sku_snapshot')])
    }, {order_id: order_ids.fetch([orgkey, r.fetch('order_number')]), shipped_quantity: r.fetch('shipped_quantity'),
        created_at: rows.fetch('nm_shipments').find { |sh| sh.fetch('shipment_key') == r.fetch('shipment_key') }.fetch('shipped_at')})
  end
  rows.fetch('nm_return_requests').each do |r|
    orgkey = r.fetch('organization')
    attrs = r.reject { |k, _| %w[organization order_number request_key].include?(k) }
    attrs[:order_id] = order_ids.fetch([orgkey, r.fetch('order_number')])
    rr = upsert.call('nm_return_requests', {organization_id: orgs.fetch(orgkey), request_key: r.fetch('request_key')}, attrs)
    return_ids[[orgkey, r.fetch('request_key')]] = rr.id
  end
  rows.fetch('nm_return_items').each do |r|
    orgkey = r.fetch('organization')
    upsert.call('nm_return_items', {
      organization_id: orgs.fetch(orgkey),
      return_request_id: return_ids.fetch([orgkey, r.fetch('request_key')]),
      order_item_id: order_item_ids.fetch([orgkey, r.fetch('order_number'), r.fetch('sku_snapshot')])
    }, {order_id: order_ids.fetch([orgkey, r.fetch('order_number')]), quantity: r.fetch('quantity')})
  end
  rows.fetch('nm_warranty_claims').each do |r|
    orgkey = r.fetch('organization')
    attrs = r.reject { |k, _| %w[organization order_number sku_snapshot claim_key].include?(k) }
    attrs[:order_item_id] = order_item_ids.fetch([orgkey, r.fetch('order_number'), r.fetch('sku_snapshot')])
    upsert.call('nm_warranty_claims', {organization_id: orgs.fetch(orgkey), claim_key: r.fetch('claim_key')}, attrs)
  end
  counts = models.transform_values(&:count)
  rows.each { |name, table_rows| raise "Count mismatch #{name}: #{counts.fetch(name)} vs #{table_rows.length}" unless counts.fetch(name) == table_rows.length }
  puts JSON.pretty_generate({status: 'SEEDED_IN_POSTGRESQL', seed: json.fetch('seed'), policy_version: json.fetch('policy_version'),
    dataset_sha256: actual_sha, adapter: ActiveRecord::Base.connection.adapter_name, counts: counts})
end
