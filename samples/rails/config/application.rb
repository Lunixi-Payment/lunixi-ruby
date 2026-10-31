# frozen_string_literal: true

require_relative 'boot'
require 'rails'
require 'active_record/railtie'
require 'action_controller/railtie'
require 'lunixi'
require_relative '../lib/lunixi_return_adapter'

module LunixiRailsSample
  class Application < Rails::Application
    config.load_defaults 8.1
    config.middleware.insert_after ActionDispatch::HostAuthorization, LunixiReturnAdapter
    config.root = File.expand_path('..', __dir__)
    config.eager_load = false
    config.secret_key_base = ENV.fetch('SECRET_KEY_BASE')
    raise 'Set DEMO_USERNAME and a DEMO_PASSWORD of at least 16 bytes' if ENV.fetch('DEMO_USERNAME').empty? || ENV.fetch('DEMO_PASSWORD').bytesize < 16

    config.hosts = ['localhost', '127.0.0.1', 'www.example.com']
    config.hosts << URI.parse(ENV.fetch('PUBLIC_ORIGIN')).host if ENV['PUBLIC_ORIGIN']
    config.force_ssl = !Rails.env.local?
    # Rails logs redirect locations at info level; the hosted checkout token is a credential.
    config.log_level = :warn
    config.filter_parameters = [/.*/]
    config.i18n.available_locales = %i[en tr]
    config.i18n.default_locale = :en
    config.active_record.encryption.primary_key = ENV.fetch('ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY')
    config.active_record.encryption.deterministic_key = ENV.fetch('ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY')
    config.active_record.encryption.key_derivation_salt = ENV.fetch('ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT')
    config.x.lunixi_client = nil
    config.x.lunixi_webhook_secret = ENV.fetch('LUNIXI_WEBHOOK_SECRET')
    config.x.lunixi_merchant_id = ENV.fetch('LUNIXI_MERCHANT_ID')
    raise 'Set LUNIXI_MERCHANT_ID' if config.x.lunixi_merchant_id.empty?

    config.action_dispatch.default_headers.merge!(
      'Referrer-Policy' => 'no-referrer', 'X-Content-Type-Options' => 'nosniff',
      'Content-Security-Policy' => "default-src 'self'; form-action 'self'; frame-ancestors 'none'"
    )
  end
end
