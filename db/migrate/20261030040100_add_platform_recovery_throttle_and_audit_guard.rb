# frozen_string_literal: true

# P0.3 security hardening: persistent throttles and dual-control recovery.
# Applied ONLY to the isolated sandbox and test databases at this stage.
class AddPlatformRecoveryThrottleAndAuditGuard < ActiveRecord::Migration[8.0]
  def up
    create_table :platform_login_throttles do |t|
      t.string :scope, null: false, limit: 20
      t.string :identity_digest, null: false, limit: 64
      t.bigint :bucket_start, null: false
      t.integer :attempts, null: false, default: 0
    end
    add_index :platform_login_throttles,
      [:scope, :identity_digest, :bucket_start],
      unique: true, name: 'idx_platform_throttle_bucket_identity'
    add_check_constraint :platform_login_throttles,
      "scope IN ('password', 'mfa') AND attempts >= 0",
      name: 'platform_throttle_valid_scope_and_attempts'

    create_table :platform_mfa_recoveries do |t|
      t.references :target_admin, null: false, foreign_key: { to_table: :platform_admins }
      t.references :initiator_admin, null: false, foreign_key: { to_table: :platform_admins }
      t.references :approver_admin, null: true, foreign_key: { to_table: :platform_admins }
      t.string :state, null: false, default: 'pending'
      t.datetime :expires_at, null: false
      t.datetime :approved_at
      t.timestamps
    end
    add_index :platform_mfa_recoveries, [:target_admin_id, :state],
      name: 'idx_platform_recovery_target_state'
    add_check_constraint :platform_mfa_recoveries,
      "state IN ('pending', 'approved')",
      name: 'platform_recovery_known_state'
    add_check_constraint :platform_mfa_recoveries,
      "target_admin_id <> initiator_admin_id AND "       "(approver_admin_id IS NULL OR "       "(approver_admin_id <> target_admin_id AND approver_admin_id <> initiator_admin_id))",
      name: 'platform_recovery_distinct_actors'

    # Even bulk SQL UPDATE/DELETE cannot silently rewrite either audit table.
    # A database OWNER/SUPERUSER could still remove triggers, so this is not WORM.
    execute <<~SQL
      CREATE FUNCTION p03_reject_audit_mutation() RETURNS trigger
      LANGUAGE plpgsql AS $$
      BEGIN
        RAISE EXCEPTION 'append-only platform audit records';
      END;
      $$;
      CREATE TRIGGER p03_security_event_append_only
        BEFORE UPDATE OR DELETE ON platform_security_events
        FOR EACH ROW EXECUTE FUNCTION p03_reject_audit_mutation();
      CREATE TRIGGER p03_platform_audit_append_only
        BEFORE UPDATE OR DELETE ON platform_audit_events
        FOR EACH ROW EXECUTE FUNCTION p03_reject_audit_mutation();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS p03_security_event_append_only ON platform_security_events;
      DROP TRIGGER IF EXISTS p03_platform_audit_append_only ON platform_audit_events;
      DROP FUNCTION IF EXISTS p03_reject_audit_mutation();
    SQL
    drop_table :platform_mfa_recoveries
    drop_table :platform_login_throttles
  end
end
