# frozen_string_literal: true
# M2: Synthetic bilingual KB. Approved M0 policies do NOT auto-approve KB draft content.
# PostgreSQL schema draft until executed on Rails 8 + PostgreSQL.
class CreateKnowledgeBase < ActiveRecord::Migration[8.0]
  def change
    create_table :knowledge_articles do |t|
      t.bigint :organization_id, null: false
      t.string :article_key, null: false
      t.string :category, null: false
      t.string :audience, null: false, default: 'public' # public, agent
      t.jsonb :policy_refs, null: false, default: []
      t.timestamps
    end
    add_foreign_key :knowledge_articles, :organizations
    add_index :knowledge_articles, [:organization_id, :article_key], unique: true, name: 'uniq_kb_article_tenant_key'
    add_index :knowledge_articles, [:organization_id, :id], unique: true
    add_check_constraint :knowledge_articles, "audience IN ('public','agent')", name: 'kb_article_audience_known'

    create_table :knowledge_article_versions do |t|
      t.bigint :organization_id, null: false
      t.bigint :knowledge_article_id, null: false
      t.string :locale, null: false
      t.integer :version_number, null: false
      t.string :title, null: false
      t.text :body, null: false
      t.string :status, null: false, default: 'draft'
      t.date :effective_from, null: false
      t.date :effective_to
      t.string :sha256, null: false
      t.string :policy_version, null: false
      t.string :source_blueprint_sha256, null: false
      t.bigint :approved_by
      t.datetime :approved_at
      t.timestamps
    end
    add_foreign_key :knowledge_article_versions, :knowledge_articles,
      column: [:organization_id, :knowledge_article_id], primary_key: [:organization_id, :id]
    add_foreign_key :knowledge_article_versions, :memberships,
      column: [:organization_id, :approved_by], primary_key: [:organization_id, :user_id]
    add_index :knowledge_article_versions, [:organization_id, :id], unique: true
    add_index :knowledge_article_versions, [:organization_id, :knowledge_article_id, :locale, :version_number],
      unique: true, name: 'uniq_kb_version_per_locale'
    add_index :knowledge_article_versions, [:organization_id, :status, :locale], name: 'index_kb_publication_filter'
    add_index :knowledge_article_versions, [:organization_id, :knowledge_article_id, :locale],
      unique: true, where: "status = 'approved'", name: 'uniq_current_published_kb_language' 
    add_check_constraint :knowledge_article_versions, "locale IN ('vi','en')", name: 'kb_version_known_locale'
    add_check_constraint :knowledge_article_versions,
      "status IN ('draft','approved','superseded','rejected')", name: 'kb_version_known_status'
    add_check_constraint :knowledge_article_versions, 'version_number >= 1', name: 'kb_version_positive'
    add_check_constraint :knowledge_article_versions,
      '(effective_to IS NULL OR effective_to >= effective_from)', name: 'kb_version_valid_effective_window'
    add_check_constraint :knowledge_article_versions,
      "((status = 'approved' AND approved_by IS NOT NULL AND approved_at IS NOT NULL) OR status <> 'approved')",
      name: 'kb_approved_requires_actor_time'

    create_table :knowledge_chunks do |t|
      t.bigint :organization_id, null: false
      t.bigint :knowledge_article_version_id, null: false
      t.integer :chunk_index, null: false
      t.text :body, null: false
      t.string :sha256, null: false
      t.string :embedding_status, null: false, default: 'not_generated'
      t.string :embedding_model_revision
      t.timestamps
    end
    add_foreign_key :knowledge_chunks, :knowledge_article_versions,
      column: [:organization_id, :knowledge_article_version_id], primary_key: [:organization_id, :id]
    add_index :knowledge_chunks, [:organization_id, :knowledge_article_version_id, :chunk_index],
      unique: true, name: 'uniq_kb_chunk_per_version'
    add_check_constraint :knowledge_chunks, 'chunk_index >= 0', name: 'kb_chunk_index_nonnegative'
    add_check_constraint :knowledge_chunks,
      "embedding_status IN ('not_generated','pending','ready','failed')", name: 'kb_chunk_embedding_status_known'
    # Built-in PostgreSQL lexical retrieval index; no pgvector extension is assumed.
    reversible do |direction|
      direction.up { execute "CREATE INDEX index_kb_chunks_fts_simple ON knowledge_chunks USING GIN (to_tsvector('simple', body))" }
      direction.down { execute 'DROP INDEX IF EXISTS index_kb_chunks_fts_simple' }
    end
  end
end
