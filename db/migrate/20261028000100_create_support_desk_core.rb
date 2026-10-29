# frozen_string_literal: true
# Rails 8 migration DRAFT: NOT EXECUTED. Apply only to a new demo database.
class CreateSupportDeskCore < ActiveRecord::Migration[8.0]
  def change
    create_table :organizations do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.string :vertical, null: false
      t.string :currency, null: false
      t.string :timezone, null: false, default: 'Asia/Ho_Chi_Minh'
      t.string :default_locale, null: false, default: 'vi'
      t.string :policy_version, null: false, default: '1.0.0'
      t.timestamps
    end
    add_index :organizations, :slug, unique: true
    add_check_constraint :organizations, "currency IN ('USD','VND')", name: 'org_currency_known'

    create_table :users do |t|
      t.string :email, null: false
      t.string :display_name
      t.timestamps
    end
    add_index :users, :email, unique: true

    tenant_table :memberships do |t|
      t.bigint :user_id, null: false
      t.string :role, null: false
    end
    add_index :memberships, [:organization_id, :user_id], unique: true
    add_foreign_key :memberships, :users
    add_check_constraint :memberships, "role IN ('owner','admin','agent','viewer')", name: 'membership_known_role'

    tenant_table :customers do |t|
      t.string :external_key, null: false
      t.string :locale, null: false, default: 'vi'
      t.string :synthetic_email, null: false
      t.string :display_name
    end
    add_index :customers, [:organization_id, :external_key], unique: true
    add_check_constraint :customers, "locale IN ('vi','en')", name: 'customer_known_locale'

    tenant_table :tickets do |t|
      t.bigint :customer_id, null: false
      t.bigint :assignee_id
      t.string :number, null: false
      t.string :category, null: false
      t.string :priority, null: false, default: 'P3'
      t.string :status, null: false, default: 'new'
      t.string :business_ref
    end
    add_index :tickets, [:organization_id, :number], unique: true
    tenant_fk :tickets, :customers, :customer_id
    # Assignment is permitted only to a member of the SAME organization.
    add_foreign_key :tickets, :memberships, column: [:organization_id, :assignee_id], primary_key: [:organization_id, :user_id]
    add_check_constraint :tickets, "priority IN ('P1','P2','P3','P4')", name: 'ticket_known_priority'
    add_check_constraint :tickets, "status IN ('new','open','pending_customer','pending_internal','resolved','closed')", name: 'ticket_known_status'

    tenant_table :ticket_messages do |t|
      t.bigint :ticket_id, null: false
      t.bigint :actor_user_id
      t.string :actor_type, null: false
      t.string :visibility, null: false
      t.string :channel, null: false, default: 'portal'
      t.text :body, null: false
      t.datetime :sent_at
      t.string :idempotency_key
    end
    tenant_fk :ticket_messages, :tickets, :ticket_id
    add_index :ticket_messages, [:organization_id, :idempotency_key], unique: true, where: 'idempotency_key IS NOT NULL', name: 'uniq_message_tenant_idempotency'
    add_check_constraint :ticket_messages, "visibility IN ('public','internal')", name: 'message_known_visibility'
  end

  private

  def tenant_table(name)
    create_table name do |t|
      t.bigint :organization_id, null: false
      yield(t)
      t.timestamps
    end
    add_foreign_key name, :organizations, column: :organization_id
    # A composite unique key is needed as the target of tenant-scoped FKs.
    add_index name, [:organization_id, :id], unique: true
  end

  def tenant_fk(from, to, key)
    add_foreign_key from, to, column: [:organization_id, key], primary_key: [:organization_id, :id]
  end
end
