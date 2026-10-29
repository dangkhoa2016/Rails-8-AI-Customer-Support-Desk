class AuditEvent < ApplicationRecord
  belongs_to :organization
  belongs_to :ticket, optional: true
  belongs_to :actor_user, class_name: 'User'
end
