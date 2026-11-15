# frozen_string_literal: true

# Shared fixtures of the physical POS payment tests: a recording transport answering from @answers
# (an accepted payment by default) and synthetic payment bodies.
module PhysicalPosPaymentSupport
  PAYMENT_ID = '0192f3a1-0000-7000-8000-000000000001'
  DEVICE_ID = '5f0c2b1e-1111-4222-8333-444455556666'
  KEY = 'pos-payment-key-0001'
  BASE = '/api/v1/physical-pos'

  def setup
    @answers = []
    @transport = TestSupport::RecordingTransport.new { |request| next_answer(request) }
    @pos = client(transport: @transport).physical_pos
  end

  def next_answer(_request)
    answer = @answers.empty? ? accepted : @answers.shift
    raise answer if answer.is_a?(Exception)

    answer
  end

  def sale(overrides = {})
    { operation: Lunixi::PhysicalPosPaymentOperation::SALE, target: { deviceId: DEVICE_ID }, amountMinor: '4500', currency: 'TRY',
      merchantReference: 'ORD-2026-000123' }.merge(overrides)
  end

  def payment(overrides = {})
    { 'paymentId' => PAYMENT_ID, 'rootPaymentId' => PAYMENT_ID, 'operation' => 'SALE', 'paymentStatus' => 'NOT_STARTED',
      'amountMinor' => '4500' }.merge(overrides)
  end

  def accepted(replayed: false)
    status = replayed ? 200 : 202
    response(status, { 'data' => { 'payment' => payment, 'replayed' => replayed }, 'statusCode' => status })
  end

  def failure(status, code, headers = {}, details = nil)
    body = { 'code' => code }
    body['details'] = details if details
    response(status, body, headers)
  end

  def gateway_calls
    @transport.calls.reject { |call| call[:uri].path == '/api/v1/auth/token' }
  end

  def assert_nothing_sent
    before = gateway_calls.size
    yield
    assert_equal before, gateway_calls.size, 'nothing may be sent'
  end
end
