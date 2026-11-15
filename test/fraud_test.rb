# frozen_string_literal: true

require_relative 'test_helper'

class FraudTest < Minitest::Test
  DECISION = { 'traceId' => 'trace_1', 'paymentId' => 'pay_1', 'decision' => 'allow' }.freeze

  def setup
    @decisions = [DECISION]
    @transport = RecordingTransport.new do |request|
      if request[:uri].path == '/api/v1/fraud/decision-logs'
        response(200, { 'data' => @decisions, 'pageInfo' => { 'hasMore' => false } })
      else
        response(200, { 'data' => {} })
      end
    end
    @sdk = client(transport: @transport)
  end

  def event(id = 'evt_1')
    { eventId: id, subjectType: 'CUSTOMER', eventType: 'payment.completed', occurredAt: '2026-11-15T10:00:00Z' }
  end

  def gateway_calls
    @transport.calls.reject { |request| request[:uri].path == '/api/v1/auth/token' }
  end

  def test_decision_log_list_and_get
    page = @sdk.fraud.decisions.list(paymentId: 'pay_1', decision: 'review', limit: 20, cursor: nil)
    assert_equal [DECISION], page['data']
    list = @transport.calls.last
    assert_equal ['GET', '/api/v1/fraud/decision-logs', 'paymentId=pay_1&decision=review&limit=20'],
                 [list[:method], list[:uri].path, list[:uri].query]

    @sdk.fraud.decisions.get('trace_1')
    assert_equal '/api/v1/fraud/decision-logs/trace_1', @transport.calls.last[:uri].path

    calls = gateway_calls.size
    assert_raises(Lunixi::ConfigurationError) { @sdk.fraud.decisions.list(tenantId: 'other') }
    assert_raises(Lunixi::ConfigurationError) { @sdk.fraud.decisions.get('') }
    assert_raises(Lunixi::ConfigurationError) { @sdk.fraud.decisions.get('trace/1') }
    assert_equal calls, gateway_calls.size
  end

  def test_latest_for_payment_reads_the_first_decision_or_nil
    assert_equal DECISION, @sdk.fraud.decisions.latest_for_payment('pay_1')
    assert_equal 'paymentId=pay_1&limit=1', @transport.calls.last[:uri].query
    @decisions = []
    assert_nil @sdk.fraud.decisions.latest_for_payment('pay_1')
    assert_raises(Lunixi::ConfigurationError) { @sdk.fraud.decisions.latest_for_payment(' ') }
  end

  def test_record_batch_sends_a_signed_json_array
    @sdk.fraud.events.record_batch([event('evt_1'), event('evt_2')], idempotency_key: idempotency_key)
    sent = @transport.calls.last
    assert_equal ['POST', '/api/v1/fraud/events/transactions/batch'], [sent[:method], sent[:uri].path]
    body = JSON.parse(sent[:body])
    assert_kind_of Array, body
    assert_equal(%w[evt_1 evt_2], body.map { |entry| entry['eventId'] })
    assert_equal idempotency_key, sent[:headers]['Idempotency-Key']
    assert sent[:headers].key?('X-Signature')
  end

  def test_record_batch_local_errors_send_nothing
    calls = gateway_calls.size
    [[], {}, [event.merge(eventId: nil)], ['evt_1'], Array.new(Lunixi::FraudEvents::BATCH_LIMIT + 1) { |index| event("evt_#{index}") }].each do |events|
      assert_raises(Lunixi::ConfigurationError) { @sdk.fraud.events.record_batch(events, idempotency_key: idempotency_key) }
    end
    assert_raises(Lunixi::ConfigurationError) { @sdk.fraud.events.record_batch([event], idempotency_key: nil) }
    assert_equal calls, gateway_calls.size
  end

  def test_record_event_and_events_record_use_the_same_signed_route
    @sdk.fraud.record_event(event, idempotency_key: idempotency_key)
    @sdk.fraud.events.record(event('evt_2'), idempotency_key: idempotency_key)
    gateway_calls.last(2).each do |sent|
      assert_equal '/api/v1/fraud/events/transactions', sent[:uri].path
      assert sent[:headers].key?('X-Signature')
    end
    assert_raises(Lunixi::ConfigurationError) { @sdk.fraud.events.record({ eventId: 'evt_3' }, idempotency_key: idempotency_key) }
  end
end
