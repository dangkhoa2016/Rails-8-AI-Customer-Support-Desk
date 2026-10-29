class TicketMessage < ApplicationRecord
  belongs_to :organization
  belongs_to :ticket
  scope :for_organization, ->(organization) { where(organization_id: organization.id) }
end
