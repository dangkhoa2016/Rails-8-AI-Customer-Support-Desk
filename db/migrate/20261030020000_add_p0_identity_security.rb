# frozen_string_literal: true
# Additive, non-destructive P0 identity/security metadata.
# Existing synthetic users are active but have no password and thus cannot authenticate.
class AddP0IdentitySecurity < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :password_digest, :string
    add_column :users, :active, :boolean, null: false, default: true
    add_column :users, :system_admin, :boolean, null: false, default: false
    add_column :memberships, :active, :boolean, null: false, default: true
    add_index :users, :system_admin, where: 'system_admin = true',
      name: 'idx_p0_platform_admins'
    add_index :memberships, [:organization_id, :active],
      name: 'idx_p0_active_memberships'
  end
end
