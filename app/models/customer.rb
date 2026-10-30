class Customer < ApplicationRecord
  belongs_to :organization
  has_many :tickets
  scope :for_organization, ->(organization) { where(organization_id: organization.id) }
  scope :active, -> { where(archived_at: nil) }
  def archived?
    archived_at.present?
  end
end
