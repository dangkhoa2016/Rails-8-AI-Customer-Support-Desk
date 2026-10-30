#!/usr/bin/env ruby
# frozen_string_literal: true

# Local-only, interactive, out-of-band operator administration.
# Usage: RAILS_ENV=sandbox bin/rails runner script/p03_platform_operator.rb create email display_name
#        RAILS_ENV=sandbox bin/rails runner script/p03_platform_operator.rb revoke email
# Never submit passwords as command-line parameters or seed a default operator.
require 'io/console'
require 'fileutils'

raise SecurityError, 'sandbox marker required' unless Rails.env.sandbox? &&
  ENV['P03_SANDBOX_MARKER'] == 'RAILS8_P03_ISOLATED_SANDBOX' &&
  ActiveRecord::Base.connection_db_config.database == 'rails8_p03_sandbox'

action, email, *name_parts = ARGV
email = email.to_s.strip.downcase
raise ArgumentError, 'invalid action' unless %w[create revoke].include?(action)
raise ArgumentError, 'invalid email' unless email.match?(/\A[^\s@]+@[^\s@]+\.[^\s@]+\z/)
raise SecurityError, 'interactive terminal required' unless IO.console

case action
when 'create'
  name = name_parts.join(' ').strip
  raise ArgumentError, 'display name required' unless name.length.between?(2, 120)
  raise SecurityError, 'identity exists' if PlatformAdmin.exists?(email: email) || User.exists?(email: email)
  password = IO.console.getpass('New operator password (min 20 chars): ')
  confirm = IO.console.getpass('Confirm password: ')
  raise SecurityError, 'password mismatch/weak' unless password == confirm &&
    password.length >= 20 && password.match?(/[A-Z]/) && password.match?(/[a-z]/) &&
    password.match?(/\d/) && password.match?(/[^a-zA-Z0-9]/)
  secret = PlatformTotp.generate_secret
  dir = '/root/.config/rails8-support-desk-p03/enrollment'
  FileUtils.mkdir_p(dir, mode: 0o700)
  raise SecurityError, 'unsafe enrollment directory' unless File.stat(dir).mode & 0o077 == 0
  uri = PlatformTotp.enrollment_uri(email: email, secret: secret)
  # Store one-time URI outside repository. Operator must delete after enrolling.
  path = File.join(dir, "operator-#{SecureRandom.hex(10)}.txt")
  File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.write(uri + "\n") }
  begin
    PlatformAdmin.transaction do
      admin = PlatformAdmin.create!(email: email, display_name: name, password: password)
      admin.enroll_mfa!(secret: secret)
      PlatformSecurityEvent.create!(platform_admin: admin, event_type: 'platform.bootstrap.created',
        procedure_id: "p03-#{SecureRandom.hex(8)}")
    end
  rescue StandardError
    File.delete(path)
    raise
  ensure
    password = confirm = secret = uri = nil
  end
  puts "Operator created in sandbox only. Enrollment URI stored in mode-0600 file: #{path}"
when 'revoke'
  raise SecurityError, 'unexpected extra args' unless name_parts.empty?
  admin = PlatformAdmin.find_by!(email: email)
  print 'Type REVOKE to disable this operator and invalidate sessions: '
  raise SecurityError, 'revoke cancelled' unless IO.console.gets&.strip == 'REVOKE'
  PlatformAdmin.transaction do
    admin.update!(active: false)
    admin.revoke_sessions!
    PlatformSecurityEvent.create!(platform_admin: admin, event_type: 'platform.bootstrap.revoked',
      procedure_id: "p03-#{SecureRandom.hex(8)}")
  end
  puts 'Operator revoked; sessions invalidated.'
end
