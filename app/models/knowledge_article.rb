class KnowledgeArticle < ApplicationRecord
  belongs_to :organization
  has_many :knowledge_article_versions, dependent: :restrict_with_exception
  validates :article_key, presence: true, uniqueness: { scope: :organization_id }
  validates :audience, inclusion: { in: %w[public agent] }
end
