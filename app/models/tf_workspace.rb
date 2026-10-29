# frozen_string_literal: true
# Tenant safety is enforced by composite FK constraints and service authorization.
# Never trust an organization_id supplied by AI or arbitrary request parameters.
class TfWorkspace < ApplicationRecord
  self.table_name = 'tf_workspaces'
  belongs_to :organization
  scope :for_organization, ->(organization) { where(organization_id: organization.id) }
end
