# frozen_string_literal: true

ENV['RAILS_ENV'] = 'test'
ENV['SECRET_KEY_BASE'] ||= 'test-only-secret-' * 8
ENV['ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY'] ||= 'test-only-primary-key-32-bytes-ok'
ENV['ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY'] ||= 'test-only-deterministic-key-long'
ENV['ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT'] ||= 'test-only-key-derivation-salt-long'
ENV['LUNIXI_WEBHOOK_SECRET'] ||= 'test-only-webhook-secret'
ENV['LUNIXI_MERCHANT_ID'] ||= 'synthetic-merchant-1'
ENV['DEMO_USERNAME'] ||= 'merchant'
ENV['DEMO_PASSWORD'] ||= 'test-only-long-password'
ENV['PUBLIC_ORIGIN'] ||= 'https://merchant.example'

require_relative '../config/environment'

ActiveRecord::Migration.verbose = false
ActiveRecord::MigrationContext.new(Rails.root.join('db/migrate')).migrate
require 'rails/test_help'
Rails.application.config.action_controller.allow_forgery_protection = true
ActionController::Base.allow_forgery_protection = true

require_relative 'fake_payments'

class RailsFlowTest < ActionDispatch::IntegrationTest
  setup do
    LunixiReceipt.delete_all
    Order.delete_all
    @order = Order.create!(amount_minor: 10_050, currency: 'TRY')
    @payments = FakePayments.new
    Rails.configuration.x.lunixi_client = Struct.new(:payments).new(@payments)
    @auth = { 'HTTP_AUTHORIZATION' => ActionController::HttpAuthentication::Basic.encode_credentials(ENV.fetch('DEMO_USERNAME'), ENV.fetch('DEMO_PASSWORD')) }
  end

  def checkout
    get order_path(@order.public_id), headers: @auth
    token = response.parsed_body.at_css('input[name="authenticity_token"]')['value']
    post checkout_order_path(@order.public_id), params: { authenticity_token: token }, headers: @auth
  end

  def signed_event(id: 'evt_123', type: 'payment.captured', data: nil)
    raw = JSON.generate(id: id, type: type, data: data || { orderId: @order.public_id, intentId: 'intent_123' })
    timestamp = Time.now.utc.iso8601
    signature = OpenSSL::HMAC.hexdigest('SHA256', ENV.fetch('LUNIXI_WEBHOOK_SECRET'), "#{id}.#{timestamp}.#{raw}")
    headers = { 'CONTENT_TYPE' => 'application/json', 'x-lunixi-event-id' => id, 'x-lunixi-event-type' => type,
                'x-lunixi-signature-timestamp' => timestamp, 'x-lunixi-signature' => "v2=#{signature}" }
    [raw, headers]
  end

  def deliver(event = signed_event)
    raw, headers = event
    post '/webhooks/lunixi', params: raw, headers: headers
  end

  def captured_payment(amount: @order.amount_minor)
    { 'id' => 'intent_123', 'merchantId' => ENV.fetch('LUNIXI_MERCHANT_ID'), 'status' => 'CAPTURED', 'orderId' => @order.public_id,
      'amount' => amount, 'currency' => 'TRY' }
  end
end
