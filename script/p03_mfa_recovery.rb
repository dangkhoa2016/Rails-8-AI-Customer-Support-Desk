#!/usr/bin/env ruby
# frozen_string_literal: true

# Private two-operator MFA recovery in the isolated sandbox. Never use public
# URLs or command-line passwords. No recovery for the last lone operator.
# Request: bin/rails runner script/p03_mfa_recovery.rb request TARGET_EMAIL INITIATOR_EMAIL
# Approve: bin/rails runner script/p03_mfa_recovery.rb approve REQUEST_ID APPROVER_EMAIL
require 'io/console'
require 'fileutils'

unless Rails.env.sandbox? && ENV['P03_SANDBOX_MARKER'] == 'RAILS8_P03_ISOLATED_SANDBOX' &&
    ActiveRecord::Base.connection_db_config.database == 'rails8_p03_sandbox'
  raise SecurityError, 'not a local P0.3 sandbox'
end
terminal = IO.console or raise SecurityError, 'interactive terminal required'
action, identifier, actor_email, *remaining = ARGV
raise ArgumentError, 'unexpected arguments' unless remaining.empty?
raise ArgumentError, 'invalid action' unless %w[request approve].include?(action)
actor_email = actor_email.to_s.strip.downcase
raise ArgumentError, 'invalid operator email' unless actor_email.match?(/\A[^\s@]+@[^\s@]+\.[^\s@]+\z/)
actor = PlatformAdmin.find_by!(email: actor_email)
raise SecurityError, 'inactive or unenrolled operator' unless actor.password_login_eligible? && actor.mfa_enrolled?
password = terminal.getpass('Independent operator password: ')
raise SecurityError, 'invalid operator credentials' unless actor.authenticate(password)
password = nil
otp = terminal.getpass('Independent operator MFA code: ')

case action
when 'request'
  target_email = identifier.to_s.strip.downcase
  raise ArgumentError, 'invalid target email' unless target_email.match?(/\A[^\s@]+@[^\s@]+\.[^\s@]+\z/)
  target = PlatformAdmin.find_by!(email: target_email)
  request = PlatformMfaRecoveryService.request!(target: target, initiator: actor, otp: otp)
  otp = nil
  puts "RECOVERY_REQUEST_CREATED id=#{request.id}; expires after 30 minutes; separate approver required"
when 'approve'
  id = Integer(identifier, 10)
  recovery = PlatformMfaRecovery.find(id)
  raise SecurityError, 'self approval prohibited' if [
    recovery.initiator_admin_id, recovery.target_admin_id
  ].include?(actor.id)
  raise SecurityError, 'request no longer valid' unless recovery.pending_and_valid?

  new_secret = PlatformTotp.generate_secret
  uri = PlatformTotp.enrollment_uri(email: recovery.target_admin.email, secret: new_secret)
  dir = '/root/.config/rails8-support-desk-p03/enrollment'
  FileUtils.mkdir_p(dir, mode: 0o700)
  raise SecurityError, 'unsafe recovery directory' unless File.stat(dir).mode & 0o077 == 0
  path = File.join(dir, "recovery-#{SecureRandom.hex(12)}.txt")
  File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.write(uri + "\n") }
  begin
    PlatformMfaRecoveryService.approve!(recovery: recovery, approver: actor,
      otp: otp, new_secret: new_secret)
  rescue Exception
    File.unlink(path) if File.exist?(path)
    raise
  ensure
    otp = new_secret = uri = nil
  end
  puts "RECOVERY_APPROVED_AND_ALL_TARGET_SESSIONS_REVOKED: private enrollment at #{path}"
  puts 'Transfer privately to the target operator; securely delete enrollment file after use.'
end
