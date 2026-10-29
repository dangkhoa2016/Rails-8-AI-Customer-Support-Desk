# frozen_string_literal: true
# Pure Ruby mapping for historical timestamps used by the M1 deterministic importer.
# Input JSON maps have string keys. ActiveRecord code can add symbol keys, so normalize
# before reading any source timeline field. No Rails dependencies: regression-testable.
require 'time'

module SupportDesk
  module M1SeedTimestamp
    module_function

    def timestamp_for(table, attrs, reference_time:)
      values = attrs.transform_keys(&:to_s)
      timestamp = case table
                  when 'nm_orders', 'nm_order_items'
                    '2026-10-20T09:00:00+07:00'
                  when 'nm_payments'
                    values['confirmed_at'] || '2026-10-20T10:00:00+07:00'
                  when 'nm_shipments'
                    values['shipped_at'] || '2026-10-21T09:00:00+07:00'
                  when 'nm_shipment_items'
                    values['created_at'] || '2026-10-21T09:00:00+07:00'
                  when 'nm_return_requests', 'nm_return_items', 'nm_warranty_claims'
                    reference_time
                  when 'tf_activation_events'
                    values['occurred_at'] || '2026-10-25T10:00:00+07:00'
                  when 'tf_api_request_events'
                    values.fetch('occurred_at')
                  when 'tf_service_incidents'
                    values.fetch('window_start')
                  when 'tf_export_jobs'
                    '2026-10-20T09:00:00+07:00'
                  else
                    '2026-10-01T09:00:00+07:00'
                  end
      raise ArgumentError, "Missing historical timestamp for #{table}" if timestamp.nil?
      Time.iso8601(timestamp.to_s)
    end
  end
end
