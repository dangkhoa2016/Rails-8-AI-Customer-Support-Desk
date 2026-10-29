# frozen_string_literal: true
# Pure deterministic rules for the synthetic M0-approved policy baseline.
# No LLM calls and no write operations. Enforcement in Rails service/DB still required.
require 'date'
require 'time'

module SupportDesk
  module PolicyRules
    module_function

    TEAMFLOW_PLANS = {
      free: {monthly_usd: 0, max_members: 3, max_active_projects: 3, storage_gb: 1, manual_csv_export: false, scheduled_csv_export: false, api_rpm: 0, sso: false},
      starter: {monthly_usd: 24, max_members: 10, max_active_projects: 20, storage_gb: 10, manual_csv_export: true, scheduled_csv_export: false, api_rpm: 0, sso: false},
      pro: {monthly_usd: 69, max_members: 30, max_active_projects: nil, storage_gb: 100, manual_csv_export: true, scheduled_csv_export: true, api_rpm: 120, sso: false},
      business: {monthly_usd: 179, max_members: 100, max_active_projects: nil, storage_gb: 1_000, manual_csv_export: true, scheduled_csv_export: true, api_rpm: 600, sso: true}
    }.freeze

    def plan_details(plan)
      TEAMFLOW_PLANS.fetch(plan.to_sym)
    end

    def paid_activation_valid?(invoice_status:, activation_result:, same_subscription:)
      invoice_status.to_s == 'paid' && activation_result.to_s == 'succeeded' && same_subscription == true
    end

    def shipping_vnd(subtotal_vnd:, discount_vnd:)
      assert_nonnegative_int!(subtotal_vnd, 'subtotal_vnd')
      assert_nonnegative_int!(discount_vnd, 'discount_vnd')
      raise ArgumentError, 'discount exceeds subtotal' if discount_vnd > subtotal_vnd

      (subtotal_vnd - discount_vnd) >= 500_000 ? 0 : 30_000
    end

    def order_totals_vnd(items:)
      raise ArgumentError, 'items must be a nonempty array' if !items.is_a?(Array) || items.empty?
      subtotal = items.sum do |i|
        assert_nonnegative_int!(i.fetch(:unit_price_snapshot_vnd), 'unit_price_snapshot_vnd')
        quantity = i.fetch(:quantity)
        raise ArgumentError, 'quantity must be positive integer' unless quantity.is_a?(Integer) && quantity.positive?
        i.fetch(:unit_price_snapshot_vnd) * quantity
      end
      discount = items.sum do |i|
        d = i.fetch(:discount_snapshot_vnd)
        assert_nonnegative_int!(d, 'discount_snapshot_vnd')
        raise ArgumentError, 'item discount exceeds gross' if d > i.fetch(:unit_price_snapshot_vnd) * i.fetch(:quantity)
        d
      end
      shipping = shipping_vnd(subtotal_vnd: subtotal, discount_vnd: discount)
      {subtotal_vnd: subtotal, discount_vnd: discount, shipping_vnd: shipping, grand_total_vnd: subtotal - discount + shipping}
    end

    def within_calendar_days?(delivered_at:, requested_at:, days:)
      raise ArgumentError, 'days must be nonnegative integer' unless days.is_a?(Integer) && days >= 0
      date_delivered = local_date(delivered_at)
      date_requested = local_date(requested_at)
      offset = (date_requested - date_delivered).to_i
      offset >= 0 && offset <= days
    end

    def warranty_eligible?(delivered_at:, requested_at:, warranty_months:)
      raise ArgumentError, 'warranty_months must be nonnegative integer' unless warranty_months.is_a?(Integer) && warranty_months >= 0
      return false if warranty_months.zero?
      local_date(requested_at).between?(local_date(delivered_at), local_date(delivered_at) >> warranty_months)
    end

    # Does not authorize a new shipment; simply interprets verified fulfillment records.
    def fully_delivered?(ordered_quantity:, shipment_rows:)
      raise ArgumentError, 'ordered quantity must be positive integer' unless ordered_quantity.is_a?(Integer) && ordered_quantity.positive?
      raise ArgumentError, 'shipment_rows must be an array' unless shipment_rows.is_a?(Array)
      total = shipment_rows.sum do |row|
        q = row.fetch(:quantity)
        raise ArgumentError, 'shipment quantity must be positive integer' unless q.is_a?(Integer) && q.positive?
        q
      end
      raise ArgumentError, 'over-shipment' if total > ordered_quantity
      shipment_rows.select { |row| row.fetch(:status).to_s == 'delivered' }.sum { |row| row.fetch(:quantity) } == ordered_quantity
    end

    def prepaid_releasable?(payment_status:)
      payment_status.to_s == 'paid'
    end

    def local_date(value)
      t = value.is_a?(Time) ? value : Time.iso8601(value.to_s)
      t.getlocal('+07:00').to_date
    end

    def assert_nonnegative_int!(value, name)
      raise ArgumentError, "#{name} must be a nonnegative integer" unless value.is_a?(Integer) && value >= 0
    end
  end
end
