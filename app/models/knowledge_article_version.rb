class KnowledgeArticleVersion < ApplicationRecord
  belongs_to :organization
  belongs_to :knowledge_article
  belongs_to :approver, class_name: 'User', foreign_key: :approved_by, optional: true
  has_many :knowledge_chunks, dependent: :restrict_with_exception
  validates :locale, inclusion: { in: %w[vi en] }
  validates :version_number, numericality: { only_integer: true, greater_than: 0 }
  validates :status, inclusion: { in: %w[draft approved superseded rejected] }
  validates :sha256, presence: true
  validate :content_digest_matches
  validate :published_content_is_immutable, on: :update

  def active_on?(date = Date.current)
    status == 'approved' && approved_by.present? && approved_at.present? &&
      effective_from <= date && (effective_to.nil? || effective_to >= date)
  end

  private

  def published_content_is_immutable
    return unless status_in_database == 'approved'
    protected_fields = %w[title body sha256 locale version_number effective_from effective_to policy_version source_blueprint_sha256 knowledge_article_id organization_id approved_at approved_by]
    if (changes.keys & protected_fields).any?
      errors.add(:base, 'published KB content is immutable; create a new version')
    end
  end

  def content_digest_matches
    return if body.blank? || sha256.blank?
    errors.add(:sha256, 'does not match body') unless Digest::SHA256.hexdigest(body) == sha256
  end
end
