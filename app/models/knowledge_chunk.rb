class KnowledgeChunk < ApplicationRecord
  belongs_to :organization
  belongs_to :knowledge_article_version
  validates :chunk_index, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :sha256, presence: true
  validate :content_digest_matches
  validate :published_chunk_is_immutable, on: :update

  private

  def published_chunk_is_immutable
    return unless knowledge_article_version&.status == 'approved'
    if (changes.keys & %w[body sha256 chunk_index knowledge_article_version_id organization_id]).any?
      errors.add(:base, 'published KB chunks are immutable; create a new article version')
    end
  end

  def content_digest_matches
    return if body.blank? || sha256.blank?
    errors.add(:sha256, 'does not match body') unless Digest::SHA256.hexdigest(body) == sha256
  end
end
