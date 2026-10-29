# frozen_string_literal: true
# Qwen3-Embedding-4B native width is 2560. Preserve the original 1024-dimension
# migration for history. No vectors existed when this migration was introduced.
class UseQwen3Embedding4bNativeDimensions < ActiveRecord::Migration[8.0]
  def up
    raise 'Refuse dimension migration with existing embeddings' unless select_value('SELECT COUNT(*) FROM knowledge_chunk_embeddings').to_i.zero?
    execute 'ALTER TABLE knowledge_chunk_embeddings ALTER COLUMN embedding TYPE vector(2560)'
  end

  def down
    raise 'Refuse downgrade with existing embeddings' unless select_value('SELECT COUNT(*) FROM knowledge_chunk_embeddings').to_i.zero?
    execute 'ALTER TABLE knowledge_chunk_embeddings ALTER COLUMN embedding TYPE vector(1024)'
  end
end
