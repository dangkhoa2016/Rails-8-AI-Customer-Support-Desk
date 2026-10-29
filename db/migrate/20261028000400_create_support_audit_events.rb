# frozen_string_literal: true
class CreateSupportAuditEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :audit_events do |t|
      t.bigint :organization_id, null: false
      t.bigint :actor_user_id, null: false
      t.bigint :ticket_id
      t.string :action, null: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :audit_events, [:organization_id, :id], unique: true
    add_index :audit_events, [:organization_id, :created_at]
    add_foreign_key :audit_events, :organizations
    add_foreign_key :audit_events, :memberships, column: [:organization_id, :actor_user_id], primary_key: [:organization_id, :user_id]
    add_foreign_key :audit_events, :tickets, column: [:organization_id, :ticket_id], primary_key: [:organization_id, :id]
  end
end
