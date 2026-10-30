# frozen_string_literal: true

# Explicit tenant-role policy. Never derive privileges from user input or an LLM.
# Global platform admins have no implicit access to tenant customer records.
class SupportDeskAccessPolicy
  ROLE_PERMISSIONS = {
    'owner' => %i[ticket_read ticket_create ticket_update ticket_reply ticket_internal_read
                  ticket_assign customer_read customer_manage kb_read kb_review ai_search
                  business_read staff_read staff_manage settings_read settings_manage audit_read],
    'admin' => %i[ticket_read ticket_create ticket_update ticket_reply ticket_internal_read
                  ticket_assign customer_read customer_manage kb_read kb_review ai_search
                  business_read staff_read staff_manage settings_read audit_read],
    'agent' => %i[ticket_read ticket_create ticket_update ticket_reply ticket_internal_read
                  customer_read kb_read ai_search business_read],
    'viewer' => %i[ticket_read customer_read kb_read]
  }.transform_values(&:freeze).freeze

  attr_reader :membership

  def initialize(membership)
    @membership = membership
  end

  def allowed?(action)
    return false unless membership && membership.user && membership.organization
    return false if membership.respond_to?(:active?) && !membership.active?
    return false if membership.user.respond_to?(:active?) && !membership.user.active?
    ROLE_PERMISSIONS.fetch(membership.role, []).include?(action.to_sym)
  end

  def may_manage_membership?(target_role:, new_role:)
    return false unless allowed?(:staff_manage)
    return false unless ROLE_PERMISSIONS.key?(target_role) && ROLE_PERMISSIONS.key?(new_role)
    return true if membership.role == 'owner'
    %w[agent viewer].include?(target_role) && %w[agent viewer].include?(new_role)
  end

  def visible_messages(relation)
    allowed?(:ticket_internal_read) ? relation : relation.where(visibility: 'public')
  end
end
