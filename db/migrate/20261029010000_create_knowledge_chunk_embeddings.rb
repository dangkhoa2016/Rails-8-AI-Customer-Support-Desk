# frozen_string_literal: true
# Semantic KB is independent of the canonical draft dataset.
# Never drops or rewrites existing KB/article/chunk rows.
class CreateKnowledgeChunkEmbeddings < ActiveRecord::Migration[8.0]
  def up
    enable_extension 'vector' unless extension_enabled?('vector')
    add_index :knowledge_chunks, [:organization_id, :id], unique: true,
      name: 'uniq_knowledge_chunks_tenant_id' unless index_exists?(:knowledge_chunks, [:organization_id, :id],
      name: 'uniq_knowledge_chunks_tenant_id')

    create_table :knowledge_chunk_embeddings do |t|
      t.bigint :organization_id, null: false
      t.bigint :knowledge_chunk_id, null: false
      t.string :model_id, null: false
      t.string :model_revision, null: false
      t.string :content_sha256, null: false
      t.column :embedding, 'vector(1024)', null: false
      t.datetime :generated_at, null: false
      t.timestamps
    end
    add_foreign_key :knowledge_chunk_embeddings, :knowledge_chunks,
      column: [:organization_id, :knowledge_chunk_id],
      primary_key: [:organization_id, :id],
      name: 'fk_chunk_embeddings_tenant'
    add_index :knowledge_chunk_embeddings,
      [:organization_id, :knowledge_chunk_id, :model_id, :model_revision],
      unique: true, name: 'uniq_chunk_embedding_model_revision'
    add_index :knowledge_chunk_embeddings, [:organization_id, :model_id, :model_revision],
      name: 'idx_embeddings_tenant_model'
    add_check_constraint :knowledge_chunk_embeddings,
      'length(content_sha256) = 64', name: 'kb_embedding_sha256_length'
    # Exact cosine search is the correctness baseline for small approved KB sets.
    # ANN/HNSW is optional until an indexed-vs-exact recall benchmark is measured.
  end

  def down
    drop_table :knowledge_chunk_embeddings
    remove_index :knowledge_chunks, name: 'uniq_knowledge_chunks_tenant_id'
    # Keep pgvector extension: another application table might rely on it.
  end
end
