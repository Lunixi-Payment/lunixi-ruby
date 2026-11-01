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

  def payment_body
    { amount: '10050', currency: 'TRY', orderId: 'order_123', callbackUrl: 'https://merchant.example/payment/return',
      basketItems: [{ id: 'item_1', name: 'Test item', itemType: 'PHYSICAL', price: '10050' }] }
  end

  def idempotency_key
    'synthetic-idempotency-key-0001'
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
