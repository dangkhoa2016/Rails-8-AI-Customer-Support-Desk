# frozen_string_literal: true

class AddPlatformOperatorSecurity < ActiveRecord::Migration[8.0]
  def change
    add_column :platform_admins, :mfa_secret_ciphertext, :text
    add_column :platform_admins, :mfa_last_used_step, :bigint
    add_column :platform_admins, :session_version, :integer, null: false, default: 0
    add_column :platform_admins, :failed_sign_in_count, :integer, null: false, default: 0
    add_column :platform_admins, :locked_until, :datetime
    add_check_constraint :platform_admins, 'session_version >= 0 AND failed_sign_in_count >= 0',
      name: 'platform_operator_security_counters_nonnegative'

    create_table :platform_security_events do |t|
      t.references :platform_admin, null: true, foreign_key: true
      t.string :event_type, null: false
      t.string :request_id
      t.string :procedure_id
      t.datetime :created_at, null: false
    end
    add_check_constraint :platform_security_events, 'length(event_type) > 3',
      name: 'platform_security_event_type_not_empty'
    add_index :platform_security_events, [:event_type, :created_at],
      name: 'idx_platform_security_event_type_time'
  end
end
