require_relative 'boot'
require 'rails/all'

Bundler.require(*Rails.groups)

module Rails8AiCustomerSupportDesk
  class Application < Rails::Application
    config.load_defaults 8.0
    config.time_zone = 'Asia/Ho_Chi_Minh'
    config.active_record.default_timezone = :utc
    config.active_record.schema_format = :sql # Preserve PostgreSQL composite FKs.
    config.i18n.available_locales = %i[vi en]
    config.i18n.default_locale = :vi
    config.generators.system_tests = nil
    config.active_job.queue_adapter = :async # Only manual support workflows in M1.
    config.eager_load_paths << Rails.root.join('app', 'services')
  end
end
