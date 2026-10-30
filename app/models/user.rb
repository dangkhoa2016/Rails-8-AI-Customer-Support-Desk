class User < ApplicationRecord
  has_many :memberships
  has_secure_password validations: false
  validates :password, length: { minimum: 14 }, if: -> { password.present? }
  validates :email, presence: true

  def password_login_eligible?
    active? && password_digest.present?
  end
end
