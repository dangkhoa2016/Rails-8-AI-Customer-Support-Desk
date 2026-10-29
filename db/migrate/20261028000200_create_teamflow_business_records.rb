# frozen_string_literal: true
# Rails 8 migration DRAFT: NOT EXECUTED. All monetary columns are integer cents.
class CreateTeamflowBusinessRecords < ActiveRecord::Migration[8.0]
  def change
    tenant_table :tf_workspaces do |t|
      t.bigint :customer_id, null: false
      t.string :workspace_key, null: false
      t.bigint :owner_user_id
    end
    add_index :tf_workspaces, [:organization_id, :workspace_key], unique: true
    tenant_fk :tf_workspaces, :customers, :customer_id
    add_foreign_key :tf_workspaces, :memberships, column: [:organization_id, :owner_user_id], primary_key: [:organization_id, :user_id]

    tenant_table :tf_subscriptions do |t|
      t.bigint :workspace_id, null: false
      t.string :plan_code, null: false, default: 'free' # effective plan
      t.string :requested_plan_code
      t.string :status, null: false, default: 'free'
      t.datetime :effective_at
      t.datetime :renew_at
      t.string :pending_change_code
    end
    add_index :tf_subscriptions, [:organization_id, :workspace_id], unique: true
    add_index :tf_subscriptions, [:organization_id, :workspace_id, :id], unique: true, name: 'tf_subscriptions_workspace_composite'
    tenant_fk :tf_subscriptions, :tf_workspaces, :workspace_id
    add_check_constraint :tf_subscriptions, "plan_code IN ('free','starter','pro','business')", name: 'tf_sub_plan_known'
    add_check_constraint :tf_subscriptions, "requested_plan_code IS NULL OR requested_plan_code IN ('free','starter','pro','business')", name: 'tf_sub_requested_plan_known'
    add_check_constraint :tf_subscriptions, "status IN ('free','active','past_due','canceled')", name: 'tf_sub_status_known'

    tenant_table :tf_invoices do |t|
      t.bigint :workspace_id, null: false
      t.bigint :subscription_id, null: false
      t.string :invoice_number, null: false
      t.bigint :total_cents, null: false
      t.string :status, null: false
      t.datetime :paid_at
    end
    add_index :tf_invoices, [:organization_id, :invoice_number], unique: true
    add_index :tf_invoices, [:organization_id, :subscription_id, :id], unique: true, name: 'tf_invoices_subscription_composite'
    tenant_fk :tf_invoices, :tf_workspaces, :workspace_id
    add_foreign_key :tf_invoices, :tf_subscriptions, column: [:organization_id, :workspace_id, :subscription_id], primary_key: [:organization_id, :workspace_id, :id]
    add_check_constraint :tf_invoices, 'total_cents >= 0', name: 'tf_invoice_positive_cents'
    add_check_constraint :tf_invoices, "status IN ('pending','paid','failed','refunded')", name: 'tf_invoice_status_known'
    add_check_constraint :tf_invoices, "status != 'paid' OR paid_at IS NOT NULL", name: 'tf_paid_requires_timestamp'

    tenant_table :tf_activation_events do |t|
      t.bigint :subscription_id, null: false
      t.bigint :invoice_id, null: false
      t.string :result, null: false
      t.datetime :occurred_at, null: false
      t.datetime :activated_at
    end
    add_index :tf_activation_events, [:organization_id, :subscription_id, :invoice_id, :result], unique: true, name: 'uniq_tf_activation_in_invoice'
    tenant_fk :tf_activation_events, :tf_subscriptions, :subscription_id
    add_foreign_key :tf_activation_events, :tf_invoices, column: [:organization_id, :subscription_id, :invoice_id], primary_key: [:organization_id, :subscription_id, :id]
    add_check_constraint :tf_activation_events, "result IN ('succeeded','failed')", name: 'tf_activation_known_result'
    add_check_constraint :tf_activation_events, "(result = 'succeeded' AND activated_at IS NOT NULL) OR (result = 'failed' AND activated_at IS NULL)", name: 'tf_activation_result_timestamp'

    tenant_table :tf_export_jobs do |t|
      t.bigint :workspace_id, null: false
      t.string :job_key, null: false
      t.string :status, null: false
      t.string :error_code
      t.datetime :completed_at
    end
    add_index :tf_export_jobs, [:organization_id, :job_key], unique: true
    tenant_fk :tf_export_jobs, :tf_workspaces, :workspace_id
    add_check_constraint :tf_export_jobs, "status IN ('queued','running','succeeded','failed')", name: 'tf_export_known_status'

    tenant_table :tf_api_request_events do |t|
      t.bigint :workspace_id, null: false
      t.string :request_id, null: false
      t.integer :status_code, null: false
      t.string :route, null: false
      t.datetime :occurred_at, null: false
    end
    add_index :tf_api_request_events, [:organization_id, :request_id], unique: true
    tenant_fk :tf_api_request_events, :tf_workspaces, :workspace_id
    add_check_constraint :tf_api_request_events, 'status_code BETWEEN 100 AND 599', name: 'tf_request_status_http'

    tenant_table :tf_service_incidents do |t|
      t.string :incident_key, null: false
      t.datetime :window_start, null: false
      t.datetime :window_end
      t.text :affected_components, null: false
      t.text :confirmed_cause
    end
    add_index :tf_service_incidents, [:organization_id, :incident_key], unique: true
    add_check_constraint :tf_service_incidents, 'window_end IS NULL OR window_end >= window_start', name: 'tf_incident_valid_interval'
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
