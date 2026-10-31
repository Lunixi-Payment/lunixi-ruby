# frozen_string_literal: true

require_relative 'test_helper'

class ClientTest < Minitest::Test
  def test_authenticates_once_and_signs_exact_payment_bytes
    transport = RecordingTransport.new { response }
    sdk = client(transport: transport)
    sdk.payments.create_intent(payment_body, idempotency_key: idempotency_key)
    sdk.payments.get('payment_123')
    assert_equal 3, transport.calls.size
    auth, create, get = transport.calls
    assert_nil auth[:body]
    refute auth[:headers].key?('Authorization')
    assert_equal 'Bearer at_TEST_synthetic', create[:headers]['Authorization']
    assert_equal idempotency_key, create[:headers]['Idempotency-Key']
    assert_equal Lunixi::Signer.digest(create[:body]), create[:headers]['Digest']
    canonical = Lunixi::Signer.canonical(create[:method], create[:uri].request_uri, create[:headers]['X-Date'], create[:headers]['X-Nonce'],
                                         create[:headers]['Digest'])
    assert TEST_KEY.verify(nil, Base64.strict_decode64(create[:headers]['X-Signature']), canonical)
    refute get[:headers].key?('X-Signature')
    refute_includes sdk.inspect, 'at_TEST_synthetic'
  end

  def test_reuses_idempotency_key_and_body_but_refreshes_nonce_on_retry
    count = 0
    delays = []
    transport = RecordingTransport.new do
      count += 1
      count < 3 ? response(503, { code: 'temporarily_unavailable' }, { 'retry-after' => '2' }) : response
    end
    sdk = client(transport: transport, sleeper: ->(seconds) { delays << seconds })
    sdk.payments.refund('pay_1', amount: 50, idempotency_key: idempotency_key)
    requests = transport.calls.drop(1)
    assert_equal [2, 2], delays
    assert_equal [idempotency_key], requests.map { |request| request[:headers]['Idempotency-Key'] }.uniq
    assert_equal 1, requests.map { |request| request[:body] }.uniq.size
    assert_equal 3, requests.map { |request| request[:headers]['X-Nonce'] }.uniq.size
  end

  def test_never_retries_unkeyed_mutation
    transport = RecordingTransport.new { raise Lunixi::TransportError, 'network unavailable' }
    assert_raises(Lunixi::TransportError) { client(transport: transport).request('POST', '/api/v1/custom/action', body: {}) }
    assert_equal 2, transport.calls.size
  end

  def test_does_not_follow_or_retry_redirects
    transport = RecordingTransport.new { response(302, {}, { 'location' => 'https://attacker.example' }) }
    assert_raises(Lunixi::RedirectError) { client(transport: transport).payments.get('pay_1') }
    assert_equal 2, transport.calls.size
    assert(transport.calls.all? { |request| request[:uri].host == 'gateway.example' })
  end

  def test_rejects_bad_paths_and_origins_before_authentication
    transport = RecordingTransport.new { response }
    %w[http://gateway.example https://user:pass@gateway.example https://gateway.example/path https://gateway.example?query=yes].each do |url|
      assert_raises(Lunixi::ConfigurationError) do
        Lunixi::Client.new(base_url: url, key_id: 'key', private_key: TEST_KEY.private_to_pem, transport: transport)
      end
    end
    sdk = client(transport: transport)
    %w[https://attacker.example/api/v1/foo //attacker.example /api/v1/../auth /api/v1/%2e%2e/auth /api/v1/%252e/auth /api/v1/foo%2fbar].each do |path|
      assert_raises(Lunixi::ConfigurationError) { sdk.request('GET', path) }
    end
    assert_raises(Lunixi::ConfigurationError) { sdk.request('GET', '/api/v1/foo', query: { q: { nested: 'bad' } }) }
    assert_empty transport.calls
  end

  def test_escapes_and_signs_query_in_the_same_order_as_it_is_sent
    transport = RecordingTransport.new { response }
    sdk = client(transport: transport)
    sdk.request('GET', '/api/v1/payments/links', query: { status: %w[ACTIVE PAUSED], search: 'a b/Şükrü' })
    request = transport.calls.last
    assert_equal '/api/v1/payments/links?status=ACTIVE&status=PAUSED&search=a+b%2F%C5%9E%C3%BCkr%C3%BC', request[:uri].request_uri
    canonical = Lunixi::Signer.canonical('GET', request[:uri].request_uri, request[:headers]['X-Date'], request[:headers]['X-Nonce'])
    assert TEST_KEY.verify(nil, Base64.strict_decode64(request[:headers]['X-Signature']), canonical)
  end

  def test_token_cache_is_synchronized_across_threads
    transport = RecordingTransport.new { response }
    sdk = client(transport: transport)
    12.times.map { Thread.new { sdk.payments.get('pay_1') } }.each(&:value)
    assert_equal(1, transport.calls.count { |request| request[:uri].path == '/api/v1/auth/token' })
    assert_equal 13, transport.calls.size
  end

  def test_expired_token_is_refreshed
    now = NOW
    transport = RecordingTransport.new { response }
    sdk = client(transport: transport, clock: -> { now })
    sdk.payments.get('pay_1')
    now += 1771
    sdk.payments.get('pay_1')
    assert_equal(2, transport.calls.count { |request| request[:uri].path == '/api/v1/auth/token' })
  end

  def test_failure_exposes_safe_identifiers_but_not_response_pii
    transport = RecordingTransport.new do
      response(422, { code: 'payment.invalid', message: 'PRIVATE_CARD_OR_CUSTOMER', details: 'PRIVATE_DETAILS' }, { 'x-request-id' => 'req_123' })
    end
    error = assert_raises(Lunixi::ValidationError) { client(transport: transport).payments.get('pay_1') }
    assert_equal 422, error.status
    assert_equal 'payment.invalid', error.code
    assert_equal 'req_123', error.request_id
    refute_includes error.full_message, 'PRIVATE_'
  end

  def test_invalid_response_json_has_no_raw_payload_in_error_or_cause
    transport = RecordingTransport.new { response(200, 'NOT_JSON_PRIVATE_CARD') }
    error = assert_raises(Lunixi::ApiError) { client(transport: transport).payments.get('pay_1') }
    assert_nil error.cause
    refute_includes error.full_message, 'NOT_JSON_PRIVATE_CARD'
  end

  def test_only_split_endpoint_interprets_running_split_response
    payload = { code: 'AWAITING_ACTION', data: { splitPaymentId: 'split_1', status: 'AWAITING_ACTION' } }
    transport = RecordingTransport.new { response(400, payload) }
    sdk = client(transport: transport)
    split = sdk.payments.split({ totalAmount: 100, currency: 'TRY', ownerRef: 'owner_1', legs: [{ amount: 100, cardToken: 'stored_token' }] },
                               idempotency_key: idempotency_key)
    assert_equal 'AWAITING_ACTION', split.dig('data', 'status')
    assert_raises(Lunixi::ValidationError) { sdk.payments.get('pay_1') }
  end
end
