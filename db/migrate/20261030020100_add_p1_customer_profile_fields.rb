# frozen_string_literal: true
# P1: additive customer profile fields, never destroy linked tickets/orders.
class AddP1CustomerProfileFields < ActiveRecord::Migration[8.0]
  def change
    add_column :customers, :company_name, :string
    add_column :customers, :contact_phone, :string
    add_column :customers, :archived_at, :datetime
    add_index :customers, [:organization_id, :archived_at],
      name: 'idx_p1_customers_tenant_archive'
  end
end
