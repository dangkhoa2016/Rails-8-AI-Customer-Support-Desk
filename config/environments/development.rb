Rails.application.configure do
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.action_controller.perform_caching = false
  config.active_support.deprecation = :log
  config.active_record.verbose_query_logs = true
  config.active_job.queue_adapter = :solid_queue if ENV['M5_ASYNC_SEARCH_ENABLE'] == 'YES'
  # Single PostgreSQL database: the queue tables are in regular migrations.

  config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }
  # Quick Tunnel is permitted only by the exact hostname in the preview gate below.
  # Opt-in private demo gate for viewing via an authenticated Colab notebook.
  # Never enables Cloudflare access or weakens synthetic demo sign-in restrictions.
  if ENV['RAILS_PRIVATE_PREVIEW'] == 'YES'
    require Rails.root.join('lib/private_colab_preview_gate')
    password = ENV.fetch('RAILS_PRIVATE_PREVIEW_PASSWORD')
    raise 'Private preview password is too short' if password.bytesize < 30
    # Cloudflare Quick Tunnel preview is opt-in, short-lived, read-only and bound
    # to the EXACT generated hostname; never enable the broad legacy wildcard.
    tunnel_host = ENV['RAILS_PREVIEW_TUNNEL_HOST'].to_s
    if ENV['RAILS_TUNNEL_READ_ONLY'] == 'YES'
      unless tunnel_host.match?(/\A[a-z0-9-]+\.trycloudflare\.com\z/)
        raise 'Exact temporary Cloudflare preview hostname required'
      end
      config.hosts << tunnel_host
    end
    config.middleware.insert_before 0, PrivateColabPreviewGate,
      password: password, tunnel_host: tunnel_host,
      read_only_tunnel: ENV['RAILS_TUNNEL_READ_ONLY'] == 'YES',
      allow_ai_search: ENV['RAILS_PREVIEW_AI_SEARCH_ALLOW'] == 'YES'
    # Colab port proxy hostname for port 3068 only, not arbitrary public domains.
    config.hosts << /\A[a-z0-9-]+-3068-colab\.googleusercontent\.com\z/
    # New Colab HTTPS port proxy: 3068-<session>.<region>.prod.r.colab.dev.
    # Anchor to THIS PORT and the Colab-specific domain; never allow arbitrary hosts.
    config.hosts << /\A3068-[a-z0-9-]+\.[a-z0-9-]+\.prod\.r\.colab\.dev\z/
  end
end
