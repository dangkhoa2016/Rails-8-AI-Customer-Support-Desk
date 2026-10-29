# frozen_string_literal: true
# M3 only: explicit opt-in, synthetic development PostgreSQL, immutable M1 references.
# Usage (AFTER read-only DB preflight): M3_SYNTHETIC_DEMO=YES bin/rails runner db/seeds/m3_synthetic_tickets.rb
require 'digest'
require 'json'
require 'time'
# Existing API-event constant conflicts with the Zeitwerk acronym inflector.
# Use an anonymous table-bound query class for that source table;
# do not change already-accepted M1 business models.
raise 'M3 importer disabled outside development' unless Rails.env.development?
raise 'M3_SYNTHETIC_DEMO=YES is required' unless ENV['M3_SYNTHETIC_DEMO'] == 'YES'
raise 'PostgreSQL required' unless ActiveRecord::Base.connection.adapter_name == 'PostgreSQL'

root = Rails.root
dataset_path = root.join('data/m3_synthetic_tickets.json')
manifest_path = root.join('data/m3_synthetic_tickets.manifest.json')
m1_path = root.join('data/m1_business_records.json')
dataset = JSON.parse(File.read(dataset_path))
manifest = JSON.parse(File.read(manifest_path))
actual_sha = Digest::SHA256.file(dataset_path).hexdigest
source_sha = Digest::SHA256.file(m1_path).hexdigest
raise 'M3 dataset checksum mismatch' unless actual_sha == manifest.fetch('dataset_sha256')
raise 'M1 business source checksum mismatch' unless source_sha == manifest.fetch('source_m1_sha256') && dataset.fetch('source_m1_sha256') == source_sha
raise 'Wrong M3 dataset kind' unless dataset.fetch('kind') == 'M3_SYNTHETIC_SUPPORT_TICKETS_V1'
raise 'Wrong policy or seed' unless dataset.fetch('policy_version') == '1.0.0' && dataset.fetch('seed') == 20_261_029
raise 'M3 is synthetic-only and cannot grant AI permissions' unless dataset.fetch('ai_business_writes') == 'PROHIBITED' && dataset.fetch('human_approval_required') == true
raise 'Not a semantic gold dataset' unless manifest.fetch('not_a_semantic_gold_dataset') == true && manifest.fetch('existing_sealed80_scope_gate') == 'BLOCKED'
tickets = dataset.fetch('tickets')
raise 'Expected precisely 240 synthetic tickets' unless tickets.length == manifest.fetch('ticket_count') && tickets.length == 240

reference_models = {
  'tf_invoices' => [TfInvoice, :invoice_number],
  'tf_workspaces' => [TfWorkspace, :workspace_key],
  'tf_export_jobs' => [TfExportJob, :job_key],
  'tf_api_request_events' => [Class.new(ApplicationRecord).tap { |klass| klass.table_name = 'tf_api_request_events' }, :request_id],
  'tf_service_incidents' => [TfServiceIncident, :incident_key],
  'nm_orders' => [NmOrder, :order_number],
  'nm_payments' => [NmPayment, :payment_key],
  'nm_shipments' => [NmShipment, :shipment_key],
  'nm_return_requests' => [NmReturnRequest, :request_key],
  'nm_warranty_claims' => [NmWarrantyClaim, :claim_key]
}.freeze
org_slugs = %w[teamflow-cloud novamart-store].freeze
valid_status = %w[new open pending_customer pending_internal resolved closed].freeze
valid_priority = %w[P1 P2 P3 P4].freeze
allowed_categories = {
  'teamflow-cloud' => %w[billing_subscription permissions_workspace exports_jobs integrations_api incidents_bugs general_howto],
  'novamart-store' => %w[order_status payment_issues shipping_exceptions returns_refunds product_warranty missing_wrong_damaged]
}.freeze

# All DB reads and consistency checks happen before the first insert.
# Transaction ensures fail-closed behavior if a mismatch appears during write.
counts = {tickets_inserted: 0, tickets_already_matching: 0, messages_inserted: 0, messages_already_matching: 0, audit_events_inserted: 0}
ActiveRecord::Base.transaction do
  orgs = Organization.where(slug: org_slugs).index_by(&:slug)
  raise 'Missing synthetic M1 organizations' unless orgs.keys.sort == org_slugs.sort
  raise 'Synthetic policy version mismatch' unless orgs.values.all? { |o| o.policy_version == '1.0.0' }
  raise 'M1 customers missing in database; refusing auto-reseed' unless Customer.where(organization_id: orgs.values.map(&:id)).count >= 100
  raise 'M1 invoices missing; refusing auto-reseed' unless TfInvoice.where(organization_id: orgs.fetch('teamflow-cloud').id).count >= 80
  raise 'M1 orders missing; refusing auto-reseed' unless NmOrder.where(organization_id: orgs.fetch('novamart-store').id).count >= 120

  verified = tickets.map do |row|
    slug = row.fetch('organization')
    raise 'Unexpected organization' unless org_slugs.include?(slug)
    org = orgs.fetch(slug)
    customer = Customer.find_by!(organization_id: org.id, external_key: row.fetch('customer_key'))
    raise 'Customer locale mismatch' unless customer.locale == row.fetch('locale')
    raise 'Unknown ticket category' unless allowed_categories.fetch(slug).include?(row.fetch('category'))
    raise 'Invalid status or priority' unless valid_status.include?(row.fetch('status')) && valid_priority.include?(row.fetch('priority'))
    raise 'M3 tickets must not represent AI decisions' unless row.fetch('synthetic') == true && row.fetch('ai_generated') == false && row.fetch('human_policy_gold').nil?
    assignee_email = row.fetch('assignee_email')
    user = User.find_by!(email: assignee_email)
    Membership.find_by!(organization_id: org.id, user_id: user.id, role: 'agent')

    table = row.fetch('source_table')
    reference = row.fetch('business_ref')
    record = if table == 'tf_subscriptions'
      workspace = TfWorkspace.find_by!(organization_id: org.id, workspace_key: reference)
      TfSubscription.find_by!(organization_id: org.id, workspace_id: workspace.id)
    else
      klass, field = reference_models.fetch(table)
      klass.find_by!({organization_id: org.id, field => reference})
    end
    raise 'Cross-tenant business reference' unless record.organization_id == org.id
    row.fetch('source_facts').each do |field, expected|
      raise "Missing source fact #{field}" unless record.has_attribute?(field)
      actual = record.public_send(field)
      # ActiveRecord normalizes timestamps to UTC, while frozen M1 JSON uses +07:00.
      # Compare instants rather than time-zone display strings.
      matches = if actual.respond_to?(:to_time) && expected.is_a?(String) && expected.match?(/\A\d{4}-\d{2}-\d{2}T/)
        actual.to_time == Time.iso8601(expected)
      else
        actual == expected
      end
      raise "M1 source fact changed: #{row.fetch('number')} #{field}" unless matches
    end

    if slug == 'teamflow-cloud' && table != 'tf_service_incidents'
      workspace = table == 'tf_workspaces' ? record :
                  table == 'tf_subscriptions' ? workspace :
                  TfWorkspace.find_by!(organization_id: org.id, id: record.workspace_id)
      raise 'Cross-customer TeamFlow business link' unless workspace.customer_id == customer.id
    elsif slug == 'novamart-store'
      order = if table == 'nm_orders'
        record
      elsif table == 'nm_warranty_claims'
        item = NmOrderItem.find_by!(organization_id: org.id, id: record.order_item_id)
        NmOrder.find_by!(organization_id: org.id, id: item.order_id)
      else
        NmOrder.find_by!(organization_id: org.id, id: record.order_id)
      end
      raise 'Cross-customer NovaMart business link' unless order.customer_id == customer.id
    end

    number = row.fetch('number')
    expected_prefix = slug == 'teamflow-cloud' ? 'TF-M3-' : 'NM-M3-'
    raise 'Invalid M3 ticket number' unless number.match?(/\A(?:TF|NM)-M3-\d{4}\z/) && number.start_with?(expected_prefix)
    created = Time.iso8601(row.fetch('created_at'))
    updated = Time.iso8601(row.fetch('updated_at'))
    raise 'Invalid historical chronology' unless created <= updated && updated < Time.iso8601(dataset.fetch('reference_time'))
    messages = row.fetch('messages')
    raise 'Unexpected message count' unless messages.size == (row.fetch('status') == 'new' ? 1 : 2)
    messages.each_with_index do |message, idx|
      sent_at = Time.iso8601(message.fetch('sent_at'))
      raise 'Invalid message chronology' unless created <= sent_at && sent_at <= updated
      raise 'Only synthetic seeded messages allowed' unless message.fetch('channel') == 'synthetic_seed'
      raise 'Unexpected message actor or visibility' unless (idx == 0 && message.fetch('actor_type') == 'customer' && message.fetch('visibility') == 'public') ||
        (idx == 1 && message.fetch('actor_type') == 'agent' && message.fetch('visibility') == 'internal')
      raise 'Invalid message body' unless message.fetch('body').length.between?(1, 10_000)
    end
    {row: row, org: org, customer: customer, user: user, created: created, updated: updated}
  end

  verified.each do |entry|
    row, org, customer, user = entry.values_at(:row, :org, :customer, :user)
    attrs = {
      organization_id: org.id, customer_id: customer.id, assignee_id: user.id,
      number: row.fetch('number'), category: row.fetch('category'),
      priority: row.fetch('priority'), status: row.fetch('status'),
      business_ref: row.fetch('business_ref')
    }
    existing = Ticket.find_by(organization_id: org.id, number: attrs.fetch(:number))
    if existing
      raise "Existing M3 ticket was modified: #{existing.number}" unless attrs.all? { |key, val| existing.public_send(key) == val }
      counts[:tickets_already_matching] += 1
      ticket = existing
    else
      ticket = Ticket.create!(attrs.merge(created_at: entry.fetch(:created), updated_at: entry.fetch(:updated)))
      counts[:tickets_inserted] += 1
      AuditEvent.create!(
        organization_id: org.id, actor_user_id: user.id, ticket_id: ticket.id,
        action: 'synthetic.ticket_seeded',
        metadata: {dataset_sha256: actual_sha, synthetic: true, no_human_approval_implied: true},
        created_at: entry.fetch(:created), updated_at: entry.fetch(:created))
      counts[:audit_events_inserted] += 1
    end
    row.fetch('messages').each do |message|
      key = message.fetch('idempotency_key')
      msg_attrs = {
        organization_id: org.id, ticket_id: ticket.id,
        actor_type: message.fetch('actor_type'),
        actor_user_id: message.fetch('actor_type') == 'agent' ? user.id : nil,
        visibility: message.fetch('visibility'), channel: 'synthetic_seed',
        body: message.fetch('body'), idempotency_key: key,
        sent_at: Time.iso8601(message.fetch('sent_at'))
      }
      previous = TicketMessage.find_by(organization_id: org.id, idempotency_key: key)
      if previous
        raise 'Seed message edited or reused by another ticket' unless msg_attrs.all? { |name, value| previous.public_send(name) == value }
        counts[:messages_already_matching] += 1
      else
        TicketMessage.create!(msg_attrs.merge(created_at: msg_attrs[:sent_at], updated_at: msg_attrs[:sent_at]))
        counts[:messages_inserted] += 1
      end
    end
  end
end
puts JSON.pretty_generate(status: 'M3_POSTGRESQL_SYNTHETIC_IMPORT_PASS', dataset_sha256: actual_sha,
                          source_m1_sha256: source_sha, counts: counts)
