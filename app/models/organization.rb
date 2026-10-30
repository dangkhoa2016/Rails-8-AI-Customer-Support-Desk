class Organization < ApplicationRecord
  has_many :memberships
  has_many :customers
  has_many :tickets
  has_many :platform_audit_events
  LIFECYCLE_STATES = %w[staging active suspended].freeze
  validates :lifecycle_state, inclusion: {in: LIFECYCLE_STATES}

  def active_for_support?
    lifecycle_state == 'active'
  end
end
