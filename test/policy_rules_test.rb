# frozen_string_literal: true
# Pure Ruby tests; these are NOT a substitute for Rails/PostgreSQL integration tests.
require 'minitest/autorun'
require_relative '../app/services/support_desk/policy_rules'

class M1PolicyRulesTest < Minitest::Test
  Rule = SupportDesk::PolicyRules

  def test_teamflow_plan_contract
    assert_equal 24, Rule.plan_details(:starter)[:monthly_usd]
    refute Rule.plan_details(:starter)[:scheduled_csv_export]
    assert Rule.plan_details(:pro)[:scheduled_csv_export]
    assert_equal 120, Rule.plan_details(:pro)[:api_rpm]
    assert_equal 600, Rule.plan_details(:business)[:api_rpm]
    refute Rule.plan_details(:pro)[:sso]
    assert Rule.plan_details(:business)[:sso]
  end

  def test_paid_invoice_does_not_imply_activation
    refute Rule.paid_activation_valid?(invoice_status: 'paid', activation_result: 'failed', same_subscription: true)
    refute Rule.paid_activation_valid?(invoice_status: 'paid', activation_result: 'succeeded', same_subscription: false)
    refute Rule.paid_activation_valid?(invoice_status: 'pending', activation_result: 'succeeded', same_subscription: true)
    assert Rule.paid_activation_valid?(invoice_status: 'paid', activation_result: 'succeeded', same_subscription: true)
  end

  def test_shipping_boundary_after_discount
    assert_equal 30_000, Rule.shipping_vnd(subtotal_vnd: 499_999, discount_vnd: 0)
    assert_equal 0, Rule.shipping_vnd(subtotal_vnd: 500_000, discount_vnd: 0)
    assert_equal 30_000, Rule.shipping_vnd(subtotal_vnd: 510_000, discount_vnd: 10_001)
    assert_raises(ArgumentError) { Rule.shipping_vnd(subtotal_vnd: 1, discount_vnd: 2) }
  end

  def test_money_snapshots
    items = [{unit_price_snapshot_vnd: 320_000, quantity: 2, discount_snapshot_vnd: 0}]
    assert_equal({subtotal_vnd: 640_000, discount_vnd: 0, shipping_vnd: 0, grand_total_vnd: 640_000}, Rule.order_totals_vnd(items: items))
    assert_raises(ArgumentError) { Rule.order_totals_vnd(items: [{unit_price_snapshot_vnd: 1.5, quantity: 1, discount_snapshot_vnd: 0}]) }
  end

  def test_seven_day_return_and_fourteen_day_damage_report
    delivered = '2026-10-01T14:00:00+07:00'
    assert Rule.within_calendar_days?(delivered_at: delivered, requested_at: '2026-10-08T23:59:59+07:00', days: 7)
    refute Rule.within_calendar_days?(delivered_at: delivered, requested_at: '2026-10-09T00:00:00+07:00', days: 7)
    assert Rule.within_calendar_days?(delivered_at: delivered, requested_at: '2026-10-15T23:00:00+07:00', days: 14)
    refute Rule.within_calendar_days?(delivered_at: delivered, requested_at: '2026-10-16T00:00:00+07:00', days: 14)
  end

  def test_warranty_distinct_from_fourteen_day_defect_reporting
    delivered = '2026-02-01T10:00:00+07:00'
    assert Rule.warranty_eligible?(delivered_at: delivered, requested_at: '2026-04-01T09:00:00+07:00', warranty_months: 12)
    refute Rule.warranty_eligible?(delivered_at: delivered, requested_at: '2026-04-01T09:00:00+07:00', warranty_months: 0)
  end

  def test_partial_shipment_not_fully_delivered
    rows = [{status: 'delivered', quantity: 1}, {status: 'in_transit', quantity: 1}]
    refute Rule.fully_delivered?(ordered_quantity: 2, shipment_rows: rows)
    assert Rule.fully_delivered?(ordered_quantity: 2, shipment_rows: [{status: 'delivered', quantity: 2}])
    assert_raises(ArgumentError) { Rule.fully_delivered?(ordered_quantity: 2, shipment_rows: [{status: 'delivered', quantity: 3}]) }
  end

  def test_only_paid_releases_order
    refute Rule.prepaid_releasable?(payment_status: 'pending')
    refute Rule.prepaid_releasable?(payment_status: 'partially_refunded')
    assert Rule.prepaid_releasable?(payment_status: 'paid')
  end
end
