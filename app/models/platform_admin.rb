# frozen_string_literal: true

# Platform operators are NOT tenant users. No memberships or customer-data access.
# Provisioning must occur through an authorized, audited out-of-band procedure.
class PlatformAdmin < ApplicationRecord
  has_secure_password

  before_validation :normalize_email
  validates :display_name, presence: true, length: { maximum: 120 }
  validates :email, presence: true, length: { maximum: 254 },
    format: { with: /\A[^\s@]+@[^\s@]+\.[^\s@]+\z/ },
    uniqueness: { case_sensitive: false }
  validates :password, length: { minimum: 14 }, if: -> { password.present? }
  validate :not_a_tenant_identity

  def password_login_eligible?
    active? && password_digest.present?
  end

  private

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
