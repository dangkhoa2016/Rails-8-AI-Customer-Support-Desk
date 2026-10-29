class Ticket < ApplicationRecord
  belongs_to :organization
  belongs_to :customer
  has_many :ticket_messages
  scope :for_organization, ->(organization) { where(organization_id: organization.id) }
end
