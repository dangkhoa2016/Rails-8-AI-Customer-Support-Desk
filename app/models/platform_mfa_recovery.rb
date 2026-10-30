# frozen_string_literal: true

# Two independent MFA-authenticated operators are required for any MFA reset.
class PlatformMfaRecovery < ApplicationRecord
  belongs_to :target_admin, class_name: 'PlatformAdmin'
  belongs_to :initiator_admin, class_name: 'PlatformAdmin'
  belongs_to :approver_admin, class_name: 'PlatformAdmin', optional: true

  validates :state, inclusion: { in: %w[pending approved] }
  validates :expires_at, presence: true
  validate :independent_actors

  def pending_and_valid?
    state == 'pending' && expires_at.future? && approver_admin_id.nil?
  end

  private

  def independent_actors
    return if target_admin_id.nil? || initiator_admin_id.nil?
    errors.add(:initiator_admin, 'must differ from target') if target_admin_id == initiator_admin_id
    if approver_admin_id && [target_admin_id, initiator_admin_id].include?(approver_admin_id)
      errors.add(:approver_admin, 'must be independent')
    end
  end
end
