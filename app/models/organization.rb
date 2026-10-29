class Organization < ApplicationRecord
  has_many :memberships
  has_many :customers
  has_many :tickets
end
