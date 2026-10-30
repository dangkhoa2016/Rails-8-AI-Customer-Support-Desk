# frozen_string_literal: true

# Strict local-only recovery: independent operator approval, each with a fresh
# non-replayable TOTP. No recovery self-service routes or default break-glass.
class PlatformMfaRecoveryService
  def self.request!(target:, initiator:, otp:)
    require_scope!
    raise SecurityError, 'target must be active and enrolled' unless target.active? && target.mfa_enrolled?
    raise SecurityError, 'independent initiator required' if target.id == initiator.id
    raise SecurityError, 'initiator must be active and enrolled' unless initiator.active? && initiator.mfa_enrolled?

    PlatformMfaRecovery.transaction do
      target.lock!
      raise SecurityError, 'target disabled during request' unless target.active?
      unless PlatformAdmin.where(active: true).where.not(id: [target.id, initiator.id])
          .where.not(mfa_secret_ciphertext: nil).exists?
        raise SecurityError, 'independent third operator not available'
      end
      raise SecurityError, 'recovery already pending' if PlatformMfaRecovery.where(
        target_admin: target, state: 'pending').where('expires_at > ?', Time.current).exists?
      raise SecurityError, 'initiator MFA invalid/reused' unless initiator.verify_mfa_once!(otp)
      recovery = PlatformMfaRecovery.create!(target_admin: target,
        initiator_admin: initiator, expires_at: 30.minutes.from_now)
      PlatformSecurityEvent.create!(platform_admin: initiator,
        event_type: 'platform.mfa_recovery.requested', procedure_id: "p03-recovery-#{recovery.id}")
      recovery
    end
  end

  def self.approve!(recovery:, approver:, otp:, new_secret:)
    require_scope!
    raise SecurityError, 'invalid generated seed' unless new_secret.match?(/\A[0-9a-f]{40}\z/)
    PlatformMfaRecovery.transaction do
      recovery.lock!
      raise SecurityError, 'recovery expired or completed' unless recovery.pending_and_valid?
      raise SecurityError, 'independent approver required' if [
        recovery.target_admin_id, recovery.initiator_admin_id
      ].include?(approver.id)
      raise SecurityError, 'approver must be active and enrolled' unless approver.active? && approver.mfa_enrolled?
      target = recovery.target_admin
      raise SecurityError, 'target disabled' unless target.active?
      raise SecurityError, 'approver MFA invalid/reused' unless approver.verify_mfa_once!(otp)
      target.enroll_mfa!(secret: new_secret) # Also revokes every existing platform session.
      recovery.update!(state: 'approved', approver_admin: approver, approved_at: Time.current)
      PlatformSecurityEvent.create!(platform_admin: approver,
        event_type: 'platform.mfa_recovery.approved', procedure_id: "p03-recovery-#{recovery.id}")
      recovery
    end
  end

  def self.require_scope!
    return if Rails.env.sandbox? &&
      ENV['P03_SANDBOX_MARKER'] == 'RAILS8_P03_ISOLATED_SANDBOX' &&
      ActiveRecord::Base.connection_db_config.database == 'rails8_p03_sandbox'
    return if Rails.env.test? && ENV['P03_RECOVERY_TEST_MODE'] == 'YES'
    raise SecurityError, 'recovery permitted only in isolated sandbox/test'
  end
  private_class_method :require_scope!
end
