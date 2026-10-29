Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = ENV['CI'] == 'true'
  config.consider_all_requests_local = true
  config.action_controller.perform_caching = false
  config.action_dispatch.show_exceptions = :rescuable
  # pgvector requires privileged extension pre-install in this Colab test DB.
  # Never let Rails schema auto-load purge test DB or try to create vector as app role.
  # Run RAILS_ENV=test bin/rails db:migrate explicitly after admin pre-install.
  config.active_record.maintain_test_schema = false
  config.active_support.deprecation = :stderr
  config.action_mailer.delivery_method = :test
end
