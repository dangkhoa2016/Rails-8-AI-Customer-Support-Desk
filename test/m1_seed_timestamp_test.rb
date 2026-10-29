# frozen_string_literal: true
require 'minitest/autorun'
require 'json'
require 'time'
require_relative '../script/m1_seed_timestamp'

class M1SeedTimestampTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  DATA = JSON.parse(File.read(File.join(ROOT, 'data/m1_business_records.json')))
  REF_TIME = DATA.fetch('reference_time')

  def test_string_keyed_api_timestamp_uses_source_record
    record = DATA.fetch('records').fetch('tf_api_request_events').first
    expected = Time.iso8601(record.fetch('occurred_at'))
    assert_equal expected, SupportDesk::M1SeedTimestamp.timestamp_for('tf_api_request_events', record, reference_time: REF_TIME)
  end

  def test_string_keyed_incident_timestamp_uses_source_record
    record = DATA.fetch('records').fetch('tf_service_incidents').first
    expected = Time.iso8601(record.fetch('window_start'))
    assert_equal expected, SupportDesk::M1SeedTimestamp.timestamp_for('tf_service_incidents', record, reference_time: REF_TIME)
  end

  def test_mixed_symbol_and_string_keys_remain_supported
    assert_equal Time.iso8601('2026-10-26T09:00:00+07:00'),
      SupportDesk::M1SeedTimestamp.timestamp_for('tf_api_request_events', {'occurred_at' => '2026-10-26T09:00:00+07:00', workspace_id: 5}, reference_time: REF_TIME)
  end

  def test_missing_required_event_timestamp_is_rejected
    assert_raises(KeyError) { SupportDesk::M1SeedTimestamp.timestamp_for('tf_api_request_events', {}, reference_time: REF_TIME) }
    assert_raises(KeyError) { SupportDesk::M1SeedTimestamp.timestamp_for('tf_service_incidents', {}, reference_time: REF_TIME) }
  end

  def test_all_dataset_rows_yield_valid_historical_timestamps
    dataset = DATA.fetch('records')
    reference = Time.iso8601(REF_TIME)
    counted = 0
    dataset.each do |table, records|
      records.each do |record|
        value = SupportDesk::M1SeedTimestamp.timestamp_for(table, record, reference_time: REF_TIME)
        assert_kind_of Time, value, "#{table} produced a non-time value"
        assert_operator value, :<=, reference, "#{table} created_at is after reference time"
        counted += 1
      end
    end
    assert_operator counted, :>=, 1_000
  end
end
