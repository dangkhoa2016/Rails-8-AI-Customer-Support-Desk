# frozen_string_literal: true

# Append-only non-PII operator authentication and out-of-band provisioning events.
class PlatformSecurityEvent < ApplicationRecord
  belongs_to :platform_admin, optional: true
  validates :event_type, presence: true
  def readonly?
    persisted?
  end
end
