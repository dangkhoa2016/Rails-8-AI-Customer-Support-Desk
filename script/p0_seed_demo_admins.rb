# frozen_string_literal: true
# Idempotent development-only synthetic administrator fixtures.
# This does NOT provision production credentials or platform administrators.
abort 'Development only' unless Rails.env.development? && ENV['P0_DEMO_ADMIN_SEED'] == 'YES'

[
  ['teamflow-cloud', 'TeamFlow Admin (Synthetic)', 'teamflow-admin@supportdesk.example.test'],
  ['novamart-store', 'NovaMart Admin (Synthetic)', 'novamart-admin@supportdesk.example.test']
].each do |slug, display_name, email|
  org = Organization.find_by!(slug: slug)
  ActiveRecord::Base.transaction do
    user = User.find_or_initialize_by(email: email)
    if user.persisted?
      abort "Conflicting existing user: #{slug}" if user.system_admin? || user.display_name != display_name
    else
      user.assign_attributes(display_name: display_name, active: true, system_admin: false)
      user.save!
    end
    membership = Membership.find_or_initialize_by(organization: org, user: user)
    if membership.persisted?
      abort "Conflicting role: #{slug}" unless membership.role == 'admin'
    else
      membership.assign_attributes(role: 'admin', active: true)
      membership.save!
    end
    puts({tenant: slug, role: membership.role, active: membership.active?,
          has_password: user.password_digest.present?, synthetic: true}.to_json)
  end
end
