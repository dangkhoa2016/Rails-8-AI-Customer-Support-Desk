# frozen_string_literal: true

# Append-only record of platform administration; do not include passwords,
# access tokens, raw customer data or unredacted email addresses in metadata.
class PlatformAuditEvent < ApplicationRecord
  belongs_to :platform_admin
  belongs_to :organization, optional: true

  validates :action, :target_type, :target_id, presence: true
  validates :metadata, presence: true

  def readonly?
    persisted?
  end
end
