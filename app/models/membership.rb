class Membership < ApplicationRecord
  belongs_to :organization
  belongs_to :user
  scope :for_organization, ->(organization) { where(organization_id: organization.id) }
end

class Membership
  def display_label
    "#{organization.name} / #{user.display_name} (#{role})"
  end
end
