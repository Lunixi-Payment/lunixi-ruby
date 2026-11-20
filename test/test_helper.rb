# frozen_string_literal: true

require 'minitest/autorun'
require 'lunixi'

module TestSupport
  TEST_KEY = OpenSSL::PKey.generate_key('ED25519')
  NOW = Time.utc(2026, 10, 31, 12).freeze

  def response(status = 200, body = { 'data' => { 'status' => 'CAPTURED' } }, headers = {})
    Lunixi::Response.new(status: status, headers: headers, body: body.is_a?(String) ? body : JSON.generate(body))
  end

  def client(transport:, **)
    Lunixi::Client.new(base_url: 'https://gateway.example', key_id: 'mk_test_sk_synthetic',
                       private_key: TEST_KEY.private_to_pem, clock: -> { NOW }, sleeper: ->(_) {}, transport: transport, **)
  end

  # Synthetic order details every payment requires (buyer, billing and shipping address).
  def order_details
    address = { contactName: 'Test Buyer', address: 'Example Street 1', city: 'Istanbul', country: 'Turkey', zipCode: '34000' }
    { buyer: { name: 'Test', surname: 'Buyer', identityNumber: '11111111111', email: 'buyer@example.com', gsmNumber: '+905350000000',
               city: 'Istanbul', country: 'Turkey', zipCode: '34000', ip: '203.0.113.10' },
      billingAddress: address, shippingAddress: address }
  end

  def basket_item(price = '10050', **fields)
    { id: 'item_1', name: 'Test item', category1: 'Test', itemType: 'PHYSICAL', price: price }.merge(fields)
  end

  def payment_body
    { amount: '10050', currency: 'TRY', orderId: 'order_123', callbackUrl: 'https://merchant.example/payment/return',
      basketItems: [basket_item] }.merge(order_details)
  end

  def idempotency_key
    'synthetic-idempotency-key-0001'
  end

  # The gateway requests a RecordingTransport saw (the token call left out).
  def api_calls(transport)
    transport.calls.reject { |call| call.fetch(:uri).path == '/api/v1/auth/token' }
  end

  def sent_json(call)
    JSON.parse(call.fetch(:body))
  end

  # A webhook body and its v2 signature headers for a synthetic secret.
  def signed_webhook(envelope, secret, event_id: 'evt_1')
    body = JSON.generate(envelope)
    timestamp = NOW.iso8601
    signature = OpenSSL::HMAC.hexdigest('SHA256', secret, "#{event_id}.#{timestamp}.#{body}")
    [body, { 'X-Lunixi-Event-Id' => event_id, 'X-Lunixi-Signature-Timestamp' => timestamp, 'X-Lunixi-Signature' => "v2=#{signature}" }]
  end

  class RecordingTransport
    attr_reader :calls

    def initialize(&handler)
      @handler = handler
      @calls = []
      @lock = Mutex.new
    end

    def call(**request)
      @lock.synchronize { @calls << request }
      if request.fetch(:uri).path == '/api/v1/auth/token'
        return Lunixi::Response.new(status: 200, headers: {}, body: JSON.generate(access_token: 'at_TEST_synthetic', expires_in: 1800))
      end

      @handler.call(request)
    end
  end
end

module Minitest
  class Test
    include TestSupport
  end
end
