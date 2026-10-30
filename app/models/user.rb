class User < ApplicationRecord
  has_many :memberships
  has_secure_password validations: false
  validates :password, length: { minimum: 14 }, if: -> { password.present? }
  validates :email, presence: true
  validate :not_a_platform_identity

  private

  def not_a_platform_identity
    return unless email.present? && PlatformAdmin.table_exists?
    errors.add(:email, 'reserved for a platform administrator') if
      PlatformAdmin.where('LOWER(email) = ?', email.strip.downcase).exists?
  end

  public

  def password_login_eligible?
    active? && password_digest.present?
  end
end
