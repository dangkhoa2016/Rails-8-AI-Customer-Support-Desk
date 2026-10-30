# frozen_string_literal: true

# Cross-process PostgreSQL throttle; no raw IP or operator emails persisted.
# Fixed 15-minute buckets; production requires further boundary/burst testing.
require 'openssl'

class PlatformLoginThrottle
  WINDOW = 15.minutes.to_i
  LIMIT = 5

  def self.allow?(scope:, address:, at: Time.current)
    raise ArgumentError, 'invalid scope' unless %w[password mfa].include?(scope)
    require_enabled!
    key = [ENV.fetch('P03_THROTTLE_HMAC_KEY')].pack('H*')
    digest = OpenSSL::HMAC.hexdigest('SHA256', key, address.to_s)
    bucket = (at.to_i / WINDOW) * WINDOW
    result = ActiveRecord::Base.connection.exec_query(
      ActiveRecord::Base.sanitize_sql_array([
        <<~SQL.squish, scope, digest, bucket
          INSERT INTO platform_login_throttles (scope, identity_digest, bucket_start, attempts)
          VALUES (?, ?, ?, 1)
          ON CONFLICT (scope, identity_digest, bucket_start)
          DO UPDATE SET attempts = platform_login_throttles.attempts + 1
          RETURNING attempts
        SQL
      ])
    )
    attempts = Integer(result.first.fetch("attempts"))
    attempts <= LIMIT
  end

  def self.require_enabled!
    unless Rails.env.sandbox? || (Rails.env.test? && ENV['P03_THROTTLE_TEST_MODE'] == 'YES')
      raise SecurityError, 'platform throttle only allowed in isolated sandbox/test'
    end
    hex = ENV.fetch('P03_THROTTLE_HMAC_KEY')
    raise SecurityError, 'invalid throttle HMAC key' unless hex.match?(/\A[0-9a-fA-F]{64}\z/)
  end
  private_class_method :require_enabled!
end
