# frozen_string_literal: true

require_relative 'test_helper'

class WebhookTest < Minitest::Test
  class TransactionalTestStore
    def initialize
      @receipts = {}
      @lock = Mutex.new
    end

    def process_once(id:, digest:)
      @lock.synchronize do
        if @receipts.key?(id)
          raise Lunixi::ReplayConflict, 'Event id collision' unless @receipts[id] == digest

          return :duplicate
        end
        yield
        @receipts[id] = digest
        :processed
      end
    end
  end

  def setup
    @secret = 'whsec_synthetic_test_only'
    @verifier = Lunixi::WebhookVerifier.new(secret: @secret, clock: -> { NOW })
    @body = JSON.generate(id: 'event_1', type: 'payment.captured', data: { amount: 100, currency: 'TRY' })
  end

  def headers(body = @body, secret: @secret, event_id: 'event_1', timestamp: NOW.iso8601)
    { 'x-lunixi-event-id' => event_id, 'x-lunixi-event-type' => 'payment.captured',
      'x-lunixi-signature-timestamp' => timestamp,
      'x-lunixi-signature' => "v2=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "#{event_id}.#{timestamp}.#{body}")}" }
  end

  def test_cross_sdk_gateway_vectors
    vectors = JSON.parse(File.read(File.join(__dir__, 'fixtures/webhook-v2-vectors.json')))
    vectors.each do |vector|
      verifier = Lunixi::WebhookVerifier.new(secret: vector['secret'], clock: -> { Time.iso8601(vector['timestamp']) })
      signed_headers = { 'x-lunixi-event-id' => vector['eventId'], 'x-lunixi-signature-timestamp' => vector['timestamp'],
                         'x-lunixi-signature' => "v2=#{vector['expectedV2']}" }
      assert_equal vector['eventId'], verifier.verify(vector['rawBody'], signed_headers).id
    end
  end

  def test_valid_event_is_immutable_and_accepts_rotation
    current = headers
    current['x-lunixi-signature'] = "v2=#{'0' * 64}, #{current['x-lunixi-signature']}"
    event = @verifier.verify(@body, current)
    assert_equal 'event_1', event.id
    assert event.frozen?
    assert event.data.frozen?
    old = headers(secret: 'previous_synthetic_secret')
    rotated = Lunixi::WebhookVerifier.new(secret: @secret, previous_secrets: ['previous_synthetic_secret'], clock: -> { NOW })
    assert_equal 'event_1', rotated.verify(@body, old).id
    refute_includes rotated.inspect, @secret
  end

  def test_tampered_body_timestamp_event_id_and_type_are_rejected
    assert_raises(Lunixi::WebhookError) { @verifier.verify(@body.sub('100', '999'), headers) }
    assert_raises(Lunixi::WebhookError) { @verifier.verify(@body, headers.merge('x-lunixi-event-id' => 'changed')) }
    assert_raises(Lunixi::WebhookError) { @verifier.verify(@body, headers.merge('x-lunixi-signature-timestamp' => (NOW + 1).iso8601)) }
    assert_raises(Lunixi::WebhookError) { @verifier.verify(@body, headers.merge('x-lunixi-event-type' => 'payment.failed')) }
    mismatched = @body.sub('event_1', 'event_2')
    assert_raises(Lunixi::WebhookError) { @verifier.verify(mismatched, headers(mismatched)) }
  end

  def test_unsigned_header_type_cannot_replace_a_missing_signed_type
    body = JSON.generate(id: 'event_1', data: { amount: 100, currency: 'TRY' })
    assert_raises(Lunixi::WebhookError) { @verifier.verify(body, headers(body)) }
  end

  def test_stale_future_missing_and_unknown_scheme_are_rejected
    [-301, 301].each do |offset|
      assert_raises(Lunixi::WebhookError) { @verifier.verify(@body, headers(timestamp: (NOW + offset).iso8601)) }
    end
    assert_raises(Lunixi::WebhookError) { @verifier.verify(@body, {}) }
    assert_raises(Lunixi::WebhookError) { @verifier.verify(@body, headers.merge('x-lunixi-signature' => 'v1=deadbeef')) }
    assert_raises(Lunixi::WebhookError) { @verifier.verify(@body, headers.merge('X-Lunixi-Event-Id' => 'event_1')) }
  end

  def test_invalid_signed_json_duplicate_keys_and_wrong_envelope_are_rejected
    ['{"id":"event_1","id":"event_2","type":"payment.captured"}', '[1,2]', 'not-json'].each do |body|
      error = assert_raises(Lunixi::WebhookError) { @verifier.verify(body, headers(body)) }
      assert_nil error.cause
    end
  end

  def test_durable_store_contract_deduplicates_and_rolls_back_failures
    store = TransactionalTestStore.new
    executions = 0
    assert_raises(RuntimeError) { @verifier.process(@body, headers, store: store) { raise 'transaction failed' } }
    assert_equal :processed, @verifier.process(@body, headers, store: store) { executions += 1 }
    assert_equal :duplicate, @verifier.process(@body, headers, store: store) { executions += 1 }
    assert_equal 1, executions
    changed = @body.sub('100', '101')
    assert_raises(Lunixi::ReplayConflict) { @verifier.process(changed, headers(changed), store: store) { executions += 1 } }
    assert_equal 1, executions
  end
end
