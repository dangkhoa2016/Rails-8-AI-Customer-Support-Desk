# frozen_string_literal: true
# M5.2: durable, isolated metadata for synthetic-only AI retrieval.
# No changes to existing KB, ticket or embedding records.
class CreateM52AISearchRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_search_runs do |t|
      t.string :public_id, null: false, limit: 36
      t.references :organization, null: false, foreign_key: true
      t.references :membership, null: false, foreign_key: true
      t.string :locale, null: false, limit: 2
      t.string :request_role, null: false, limit: 12
      t.string :status, null: false, default: 'queued', limit: 20
      t.text :query_text, null: false
      t.string :query_sha256, null: false, limit: 64
      t.jsonb :result_hits, null: false, default: []
      t.integer :attempts, null: false, default: 0
      t.integer :elapsed_ms
      t.string :error_code, limit: 64
      t.datetime :started_at
      t.datetime :finished_at
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :ai_search_runs, :public_id, unique: true
    add_index :ai_search_runs, [:organization_id, :membership_id, :created_at],
              name: 'idx_m52_search_runs_tenant_member'
    add_index :ai_search_runs, [:status, :started_at], name: 'idx_m52_search_runs_stale'
    add_check_constraint :ai_search_runs,
      "status IN ('queued', 'running', 'retrying', 'succeeded', 'failed')",
      name: 'm52_search_status'
    add_check_constraint :ai_search_runs, "attempts BETWEEN 0 AND 2", name: 'm52_search_attempts'
    add_check_constraint :ai_search_runs, "locale IN ('vi', 'en')", name: 'm52_search_locale'
    add_check_constraint :ai_search_runs, 'length(query_sha256) = 64', name: 'm52_search_sha'
    add_check_constraint :ai_search_runs, "length(query_text) BETWEEN 12 AND 300",
      name: 'm52_search_query_bounds'
  end
end
