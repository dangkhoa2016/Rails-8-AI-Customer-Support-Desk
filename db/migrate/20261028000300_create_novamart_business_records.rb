# frozen_string_literal: true
# Rails 8 migration DRAFT: NOT EXECUTED. Monetary amounts stored as integer VND.
class CreateNovamartBusinessRecords < ActiveRecord::Migration[8.0]
  def change
    tenant_table :nm_products do |t|
      t.string :sku, null: false
      t.string :name, null: false
      t.bigint :current_price_vnd, null: false
      t.integer :stock, null: false, default: 0
      t.integer :warranty_months, null: false, default: 0
      t.boolean :active, null: false, default: true
    end
    add_index :nm_products, [:organization_id, :sku], unique: true
    add_check_constraint :nm_products, 'current_price_vnd >= 0 AND stock >= 0 AND warranty_months >= 0', name: 'nm_product_nonnegative'

    tenant_table :nm_orders do |t|
      t.bigint :customer_id, null: false
      t.string :order_number, null: false
      t.string :status, null: false, default: 'pending_payment'
      t.bigint :subtotal_vnd, null: false, default: 0
      t.bigint :discount_vnd, null: false, default: 0
      t.bigint :shipping_vnd, null: false, default: 0
      t.bigint :grand_total_vnd, null: false, default: 0
    end
    add_index :nm_orders, [:organization_id, :order_number], unique: true
    tenant_fk :nm_orders, :customers, :customer_id
    add_check_constraint :nm_orders, "status IN ('pending_payment','confirmed','packing','shipped','delivered','canceled')", name: 'nm_order_known_status'
    add_check_constraint :nm_orders, 'subtotal_vnd >= 0 AND discount_vnd >= 0 AND discount_vnd <= subtotal_vnd AND shipping_vnd >= 0 AND grand_total_vnd = subtotal_vnd - discount_vnd + shipping_vnd', name: 'nm_order_totals_consistent'
    add_check_constraint :nm_orders, 'shipping_vnd = CASE WHEN subtotal_vnd - discount_vnd >= 500000 THEN 0 ELSE 30000 END', name: 'nm_standard_shipping_rule'

    tenant_table :nm_order_items do |t|
      t.bigint :order_id, null: false
      t.string :sku_snapshot, null: false
      t.bigint :unit_price_snapshot_vnd, null: false
      t.integer :quantity, null: false
      t.bigint :discount_snapshot_vnd, null: false, default: 0
    end
    add_index :nm_order_items, [:organization_id, :order_id, :id], unique: true, name: 'nm_items_order_composite'
    add_index :nm_order_items, [:organization_id, :order_id, :sku_snapshot], unique: true, name: 'uniq_nm_order_item_sku_snapshot'
    tenant_fk :nm_order_items, :nm_orders, :order_id
    add_check_constraint :nm_order_items, 'unit_price_snapshot_vnd >= 0 AND quantity > 0 AND discount_snapshot_vnd >= 0 AND discount_snapshot_vnd <= unit_price_snapshot_vnd * quantity', name: 'nm_item_nonnegative_money'

    tenant_table :nm_payments do |t|
      t.bigint :order_id, null: false
      t.string :payment_key, null: false
      t.string :status, null: false
      t.bigint :amount_vnd, null: false
      t.datetime :confirmed_at
    end
    add_index :nm_payments, [:organization_id, :payment_key], unique: true
    tenant_fk :nm_payments, :nm_orders, :order_id
    add_check_constraint :nm_payments, "status IN ('pending','paid','failed','partially_refunded','refunded')", name: 'nm_payment_known_status'
    add_check_constraint :nm_payments, 'amount_vnd >= 0', name: 'nm_payment_nonnegative'
    add_check_constraint :nm_payments, "status != 'paid' OR confirmed_at IS NOT NULL", name: 'nm_payment_paid_at'

    tenant_table :nm_shipments do |t|
      t.bigint :order_id, null: false
      t.string :shipment_key, null: false
      t.string :carrier_label
      t.string :status, null: false
      t.datetime :shipped_at
      t.datetime :delivered_at
    end
    add_index :nm_shipments, [:organization_id, :shipment_key], unique: true
    add_index :nm_shipments, [:organization_id, :order_id, :id], unique: true, name: 'nm_ships_order_composite'
    tenant_fk :nm_shipments, :nm_orders, :order_id
    add_check_constraint :nm_shipments, "status IN ('label_created','in_transit','delivered','exception')", name: 'nm_shipment_known_status'
    add_check_constraint :nm_shipments, "status != 'delivered' OR delivered_at IS NOT NULL", name: 'nm_shipment_delivered_at'

    tenant_table :nm_shipment_items do |t|
      t.bigint :order_id, null: false
      t.bigint :shipment_id, null: false
      t.bigint :order_item_id, null: false
      t.integer :shipped_quantity, null: false
    end
    add_index :nm_shipment_items, [:organization_id, :shipment_id, :order_item_id], unique: true, name: 'uniq_nm_ship_item'
    add_foreign_key :nm_shipment_items, :nm_shipments, column: [:organization_id, :order_id, :shipment_id], primary_key: [:organization_id, :order_id, :id]
    add_foreign_key :nm_shipment_items, :nm_order_items, column: [:organization_id, :order_id, :order_item_id], primary_key: [:organization_id, :order_id, :id]
    add_check_constraint :nm_shipment_items, 'shipped_quantity > 0', name: 'nm_shipped_quantity_positive'
    # SUM(shipped_quantity) <= quantity is cross-row: enforce in transaction-locked service + tests.

    tenant_table :nm_return_requests do |t|
      t.bigint :order_id, null: false
      t.string :request_key, null: false
      t.string :reason, null: false
      t.string :status, null: false, default: 'requested'
      t.bigint :reviewed_by
    end
    add_index :nm_return_requests, [:organization_id, :request_key], unique: true
    add_index :nm_return_requests, [:organization_id, :order_id, :id], unique: true, name: 'nm_returns_order_composite'
    tenant_fk :nm_return_requests, :nm_orders, :order_id
    add_foreign_key :nm_return_requests, :memberships, column: [:organization_id, :reviewed_by], primary_key: [:organization_id, :user_id]
    add_check_constraint :nm_return_requests, "status IN ('requested','under_review','approved','rejected','received','refunded')", name: 'nm_return_known_status'

    tenant_table :nm_return_items do |t|
      t.bigint :order_id, null: false
      t.bigint :return_request_id, null: false
      t.bigint :order_item_id, null: false
      t.integer :quantity, null: false
    end
    add_index :nm_return_items, [:organization_id, :return_request_id, :order_item_id], unique: true, name: 'uniq_nm_return_item'
    add_foreign_key :nm_return_items, :nm_return_requests, column: [:organization_id, :order_id, :return_request_id], primary_key: [:organization_id, :order_id, :id]
    add_foreign_key :nm_return_items, :nm_order_items, column: [:organization_id, :order_id, :order_item_id], primary_key: [:organization_id, :order_id, :id]
    add_check_constraint :nm_return_items, 'quantity > 0', name: 'nm_return_quantity_positive'

    tenant_table :nm_warranty_claims do |t|
      t.bigint :order_item_id, null: false
      t.string :claim_key, null: false
      t.string :status, null: false
      t.bigint :reviewed_by
    end
    add_index :nm_warranty_claims, [:organization_id, :claim_key], unique: true
    tenant_fk :nm_warranty_claims, :nm_order_items, :order_item_id
    add_foreign_key :nm_warranty_claims, :memberships, column: [:organization_id, :reviewed_by], primary_key: [:organization_id, :user_id]
  end

  private
  def tenant_table(name)
    create_table name do |t|
      t.bigint :organization_id, null: false
      yield(t)
      t.timestamps
    end
    add_foreign_key name, :organizations, column: :organization_id
    add_index name, [:organization_id, :id], unique: true
  end
  def tenant_fk(from, to, key)
    add_foreign_key from, to, column: [:organization_id, key], primary_key: [:organization_id, :id]
  end
end
