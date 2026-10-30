# frozen_string_literal: true

# Isolated local-only development of platform administration. Never exposed via Tunnel.
Rails.application.configure do
  raise SecurityError, 'P0.3 sandbox marker missing' unless ENV['P03_SANDBOX_MARKER'] == 'RAILS8_P03_ISOLATED_SANDBOX'
  raise SecurityError, 'P0.3 sandbox local-only opt-in missing' unless ENV['P03_SANDBOX_LOCAL_ONLY'] == 'YES'
  raise SecurityError, 'P0.3 sandbox database mismatch' unless ENV['PGDATABASE'] == 'rails8_p03_sandbox'
  raise SecurityError, 'P0.3 dedicated DB role mismatch' unless ENV['PGUSER'] == 'rails8_p03_operator'
  raise SecurityError, 'no platform authentication opt-in' unless ENV['P0_PLATFORM_AUTH_ENABLE'] == 'YES'
  raise SecurityError, 'MFA encryption key missing' unless ENV.fetch('P03_MFA_ENCRYPTION_KEY', '').match?(/\A[0-9a-fA-F]{64}\z/)

  raise SecurityError, 'independent throttle HMAC key missing' unless ENV.fetch('P03_THROTTLE_HMAC_KEY', '').match?(/\A[0-9a-fA-F]{64}\z/)

  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.force_ssl = false # Loopback HTTP ONLY; host firewall below forbids public exposure.
  config.log_level = :info
  config.cache_store = :memory_store, { size: 16.megabytes } # Never share throttle counters with demo/test.
  config.active_job.queue_adapter = :test
  config.action_controller.perform_caching = false
  config.active_support.report_deprecations = false
  config.hosts = ['127.0.0.1', 'localhost']
  config.session_store :cookie_store, key: '_rails8_p03_operator_sandbox_session',
    same_site: :lax, secure: false, httponly: true
  require Rails.root.join('lib/p03_sandbox_local_gate')
  config.middleware.insert_before 0, P03SandboxLocalGate
end
