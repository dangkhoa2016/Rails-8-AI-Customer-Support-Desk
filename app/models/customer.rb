class Customer < ApplicationRecord
  belongs_to :organization
  has_many :tickets
  scope :for_organization, ->(organization) { where(organization_id: organization.id) }
end
