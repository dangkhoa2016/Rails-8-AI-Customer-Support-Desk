# frozen_string_literal: true

# Platform identities never inherit tenant User, Membership, ticket or KB access.
class PlatformAdmin < ApplicationRecord
  has_secure_password

  before_validation :normalize_email
  before_update :invalidate_sessions_on_credential_or_active_change
  validates :display_name, presence: true, length: { maximum: 120 }
  validates :email, presence: true, length: { maximum: 254 },
    format: { with: /\A[^\s@]+@[^\s@]+\.[^\s@]+\z/ },
    uniqueness: { case_sensitive: false }
  validates :password, length: { minimum: 14 }, if: -> { password.present? }
  validate :not_a_tenant_identity

  def password_login_eligible?
    active? && password_digest.present? && (locked_until.nil? || locked_until <= Time.current)
  end

  def record_failed_password!
    with_lock do
      new_count = locked_until && locked_until < Time.current ? 1 : failed_sign_in_count + 1
      update!(failed_sign_in_count: new_count, locked_until: new_count >= 5 ? 15.minutes.from_now : nil)
    end
  end

  def clear_failed_password!
    update!(failed_sign_in_count: 0, locked_until: nil) if failed_sign_in_count.positive? || locked_until.present?
  end

  def mfa_enrolled?
    mfa_secret_ciphertext.present?
  end

  def enroll_mfa!(secret:)
    update!(mfa_secret_ciphertext: PlatformTotp.encrypted(secret),
      mfa_last_used_step: nil, session_version: session_version + 1)
  end

  def verify_mfa_once!(code, now: Time.current)
    return false unless mfa_enrolled? && active?
    with_lock do
      secret = PlatformTotp.decrypted(mfa_secret_ciphertext)
      step = PlatformTotp.valid_step(secret, code, now: now, last_step: mfa_last_used_step)
      if step
        update!(mfa_last_used_step: step)
        true
      else
        false
      end
    end
  end

  def revoke_sessions!
    with_lock { update!(session_version: session_version + 1) }
  end

  private

  def invalidate_sessions_on_credential_or_active_change
    if will_save_change_to_password_digest? || will_save_change_to_active?
      self.session_version += 1
    end
  end

  def normalize_email
    self.email = email.to_s.strip.downcase
  end

  def not_a_tenant_identity
    return if email.blank?
    if User.where('LOWER(email) = ?', email).exists?
      errors.add(:email, 'must not belong to a tenant user')
    end
  end
end
