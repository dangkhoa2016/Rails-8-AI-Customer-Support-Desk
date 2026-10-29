# frozen_string_literal: true
# The embedding belongs to an immutable KB chunk and a specific pinned model revision.
# A superseded/draft/expired article is never eligible for retrieval merely because
# an embedding row still exists.
class KnowledgeChunkEmbedding < ApplicationRecord
  belongs_to :organization
  belongs_to :knowledge_chunk
  validates :model_id, :model_revision, :content_sha256, presence: true
  validates :content_sha256, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :knowledge_chunk_id, uniqueness: {
    scope: [:organization_id, :model_id, :model_revision]
  }
  validate :tenant_and_digest_match

  private

  def tenant_and_digest_match
    return unless knowledge_chunk
    errors.add(:organization_id, 'must match chunk organization') if knowledge_chunk.organization_id != organization_id
    errors.add(:content_sha256, 'must match chunk content') if knowledge_chunk.sha256 != content_sha256
  end
end
