# frozen_string_literal: true
# Additive platform lifecycle and immutable audit trail. Does not change approved M0 policies.
class AddPlatformTenantLifecycleAndAudit < ActiveRecord::Migration[8.0]
  def change
    add_column :organizations, :lifecycle_state, :string, null: false, default: 'active'
    add_column :organizations, :lifecycle_changed_at, :datetime
    add_check_constraint :organizations,
      "lifecycle_state IN ('staging','active','suspended')",
      name: 'organization_lifecycle_known_state'
    add_index :organizations, :lifecycle_state, name: 'idx_platform_org_lifecycle'

    create_table :platform_audit_events do |t|
      t.references :platform_admin, null: false, foreign_key: true
      t.references :organization, null: true, foreign_key: true
      t.string :action, null: false, limit: 100
      t.string :target_type, null: false, limit: 60
      t.bigint :target_id, null: false
      t.jsonb :metadata, null: false, default: {}
      t.string :request_id, limit: 100
      t.timestamps
    end
    add_index :platform_audit_events, [:organization_id, :created_at],
      name: 'idx_platform_audits_tenant_time'
    add_index :platform_audit_events, [:action, :created_at],
      name: 'idx_platform_audits_action_time'
    add_check_constraint :platform_audit_events, "length(action) > 3",
      name: 'platform_audit_nonempty_action'
  end
end
