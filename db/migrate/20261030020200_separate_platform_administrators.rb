# frozen_string_literal: true
# P0.1: Platform identities have their own persistence, authentication and session.
# Migration deliberately fails closed if legacy platform accounts exist.
class SeparatePlatformAdministrators < ActiveRecord::Migration[8.0]
  def up
    existing = select_value('SELECT COUNT(*) FROM users WHERE system_admin = TRUE').to_i
    raise 'Legacy platform accounts require explicit audited migration first' if existing.positive?

    create_table :platform_admins do |t|
      t.string :email, null: false
      t.string :display_name, null: false
      t.string :password_digest, null: false
      t.boolean :active, null: false, default: true
      t.datetime :last_sign_in_at
      t.timestamps
    end
    add_index :platform_admins, 'LOWER(email)', unique: true,
      name: 'idx_platform_admins_normalized_email'
    add_check_constraint :platform_admins, "length(password_digest) > 30",
      name: 'platform_admin_password_digest_present'

    remove_index :users, name: 'idx_p0_platform_admins'
    remove_column :users, :system_admin, :boolean, default: false, null: false
  end

  def down
    add_column :users, :system_admin, :boolean, null: false, default: false
    add_index :users, :system_admin, where: 'system_admin = true',
      name: 'idx_p0_platform_admins'
    drop_table :platform_admins
  end
end
