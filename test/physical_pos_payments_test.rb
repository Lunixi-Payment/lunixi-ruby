# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'physical_pos_payment_support'

# Physical POS payment writes: request bodies, the Idempotency-Key rule, 202 / 200, the attempt loop of
# the payment writes (an uncertain outcome is never lost) and card-data refusal. Reads, filters and
# end-of-day are in physical_pos_reads_test.rb. Ids and values are synthetic.
class PhysicalPosPaymentsTest < Minitest::Test
  include PhysicalPosPaymentSupport

  # ── create_payment ───────────────────────────────────────────────────────

  def test_create_payment_sends_the_body_in_field_order_with_the_key
    result = @pos.create_payment(sale(items: [{ lineNo: 1, name: 'Tea', quantityMilli: 2000, unitCode: 'C62', unitPriceMinor: '2250',
                                                taxGroupCode: 'VAT10', lineTotalMinor: '4500' }],
                                      allowDuplicateReference: false, interaction: nil), idempotency_key: KEY)
    sent = gateway_calls.last
    assert_equal ['POST', "#{BASE}/payments"], [sent[:method], sent[:uri].path]
    assert_equal KEY, sent[:headers]['Idempotency-Key']
    assert sent[:headers].key?('X-Signature')
    assert_equal({ 'operation' => 'SALE', 'target' => { 'deviceId' => DEVICE_ID }, 'amountMinor' => '4500', 'currency' => 'TRY',
                   'merchantReference' => 'ORD-2026-000123', 'allowDuplicateReference' => false,
                   'items' => [{ 'lineNo' => 1, 'name' => 'Tea', 'quantityMilli' => 2000, 'unitCode' => 'C62', 'unitPriceMinor' => '2250',
                                 'taxGroupCode' => 'VAT10', 'lineTotalMinor' => '4500' }],
                   'interaction' => nil }, JSON.parse(sent[:body]))
    assert_equal [202, false, true, KEY], [result.status_code, result.replayed, result.accepted?, result.idempotency_key]
    assert_equal PAYMENT_ID, result.payment['paymentId']
  end

  def test_create_payment_takes_a_provider_collected_card
    @pos.create_payment(sale(instrument: 'MEAL_CARD', interaction: 'CODE_DISPLAY', terminalProviderId: 'tp_1',
                             target: { vendor_code: 'VENDOR', serial_number: 'SN-1' }), idempotency_key: KEY)
    body = JSON.parse(gateway_calls.last[:body])
    assert_equal({ 'vendorCode' => 'VENDOR', 'serialNumber' => 'SN-1' }, body['target'])
    assert_equal %w[MEAL_CARD CODE_DISPLAY tp_1], body.values_at('instrument', 'interaction', 'terminalProviderId')
  end

  def test_replay_is_200_with_replayed_true
    @answers << accepted(replayed: true)
    result = @pos.create_payment(sale, idempotency_key: KEY)
    assert_equal [200, true, false], [result.status_code, result.replayed?, result.accepted?]
  end

  def test_status_falls_back_to_the_replayed_flag
    @answers << response(200, { 'data' => { 'payment' => payment, 'replayed' => true } })
    @answers << response(202, { 'data' => { 'payment' => payment } })
    assert_equal 200, @pos.create_payment(sale, idempotency_key: KEY).status_code
    assert_equal 202, @pos.create_payment(sale, idempotency_key: KEY).status_code
  end

  def test_payment_writes_require_a_valid_key_and_send_it_unchanged
    assert_nothing_sent do
      assert_raises(Lunixi::ConfigurationError) { @pos.create_payment(sale) }
      assert_raises(Lunixi::ConfigurationError) { @pos.create_reversal(PAYMENT_ID, { operation: 'VOID', currency: 'TRY' }) }
      [' pos-key-1', 'pos-key-1 ', 'short', '', 'pos key 01', 'x' * 201].each do |key|
        assert_raises(Lunixi::ConfigurationError) { @pos.create_payment(sale, idempotency_key: key) }
      end
    end
    @pos.create_payment(sale, idempotency_key: 'pos-key-1')
    assert_equal 'pos-key-1', gateway_calls.last[:headers]['Idempotency-Key']
  end

  def test_money_is_a_canonical_string
    assert_nothing_sent do
      [4500, '04500', '', nil, '45.00', '-1', '0'].each do |amount|
        assert_raises(Lunixi::ConfigurationError, amount.inspect) { @pos.create_payment(sale(amountMinor: amount), idempotency_key: KEY) }
      end
      assert_raises(Lunixi::ConfigurationError) do
        @pos.create_payment(sale(items: [{ lineNo: 1, name: 'Tea', quantityMilli: 1000, unitCode: 'C62', unitPriceMinor: 4500,
                                           taxGroupCode: 'VAT10', lineTotalMinor: '4500' }]), idempotency_key: KEY)
      end
    end
  end

  def test_local_errors_send_nothing
    assert_nothing_sent do
      assert_raises(Lunixi::ConfigurationError) { @pos.create_payment(sale(environment: 'LIVE'), idempotency_key: KEY) }
      assert_raises(Lunixi::ConfigurationError) { @pos.create_payment(sale.except(:target), idempotency_key: KEY) }
      assert_raises(Lunixi::ConfigurationError) { @pos.create_payment(sale(target: { terminalId: 't' }), idempotency_key: KEY) }
      assert_raises(Lunixi::ConfigurationError) { @pos.create_payment(sale(installmentCount: '3'), idempotency_key: KEY) }
      assert_raises(Lunixi::ConfigurationError) { @pos.create_payment(sale(items: []), idempotency_key: KEY) }
      assert_raises(Lunixi::ConfigurationError) { @pos.create_payment(sale(items: [{ lineNo: 1 }]), idempotency_key: KEY) }
      assert_raises(Lunixi::ConfigurationError) { @pos.create_payment(sale(operation: ''), idempotency_key: KEY) }
      assert_raises(Lunixi::ConfigurationError) { @pos.create_payment([sale], idempotency_key: KEY) }
      assert_raises(Lunixi::ConfigurationError) { @pos.create_payment(sale(merchant_reference: 'ORD-2'), idempotency_key: KEY) }
      assert_raises(Lunixi::ConfigurationError) { @pos.get_payment('..') }
      assert_raises(Lunixi::ConfigurationError) { @pos.get_payment('') }
      assert_raises(Lunixi::ConfigurationError) { @pos.get_payment('a/b') }
    end
  end

  # ── Card data ────────────────────────────────────────────────────────────

  def test_card_data_is_refused_before_sending
    cases = {
      sale(pan: '4111111111111111') => 'pan',
      sale(target: { deviceId: DEVICE_ID, cardNumber: 'x' }) => 'target.cardNumber',
      sale(merchantReference: 'kart 4111 1111 1111 1111') => 'merchantReference',
      sale(items: [{ lineNo: 1, name: 'Card 4111111111111111', quantityMilli: 1000, unitCode: 'C62', unitPriceMinor: '4500',
                     taxGroupCode: 'VAT10', lineTotalMinor: '4500' }]) => 'items[0].name',
      sale(items: [{ lineNo: 1, name: 'Tea', quantityMilli: 1000, unitCode: 'C62', unitPriceMinor: '4500',
                     taxGroupCode: '4111111111111111', lineTotalMinor: '4500' }]) => 'items[0].taxGroupCode'
    }
    assert_nothing_sent do
      cases.each do |request, field|
        error = assert_raises(Lunixi::PhysicalPosCardDataRejectedError) { @pos.create_payment(request, idempotency_key: KEY) }
        assert_equal [field, 0, Lunixi::PhysicalPosCardDataRejectedError::CODE], [error.field, error.status, error.code]
        refute_includes error.message, '4111'
      end
      assert_raises(Lunixi::PhysicalPosCardDataRejectedError) { @pos.list_payments(merchantReference: '4111111111111111') }
      assert_raises(Lunixi::PhysicalPosCardDataRejectedError) { @pos.list_payments(cvv: '123') }
    end
  end

  def test_an_item_barcode_is_not_a_card_number
    item = { lineNo: 1, name: 'Simit 8691234567012', quantityMilli: 1000, unitCode: 'C62', unitPriceMinor: '4500',
             taxGroupCode: 'VAT10', lineTotalMinor: '4500', barcode: '8691234567012' }
    @pos.create_payment(sale(items: [item]), idempotency_key: KEY)
    assert_equal 'Simit 8691234567012', JSON.parse(gateway_calls.last[:body]).dig('items', 0, 'name')
  end

  def test_gateway_card_data_answer_is_typed
    @answers << failure(400, 'physical_pos.payment.card_data_rejected', {}, { 'field' => 'items[0].name' })
    error = assert_raises(Lunixi::PhysicalPosCardDataRejectedError) { @pos.create_payment(sale, idempotency_key: KEY) }
    assert_equal [400, 'items[0].name', KEY], [error.status, error.field, error.idempotency_key]
    assert_equal 1, gateway_calls.size
  end

  # ── Uncertain outcomes ───────────────────────────────────────────────────

  def test_network_failure_then_replay_returns_the_payment_with_the_same_key
    @answers << Lunixi::TransportError.new('reset')
    @answers << accepted(replayed: true)
    result = @pos.create_payment(sale, idempotency_key: KEY)
    assert_equal [200, true], [result.status_code, result.replayed]
    calls = gateway_calls
    assert_equal 2, calls.size
    assert_equal([KEY, KEY], calls.map { |call| call[:headers]['Idempotency-Key'] })
    assert_equal 1, calls.map { |call| call[:body] }.uniq.size
  end

  def test_every_attempt_uncertain_raises_outcome_unknown
    3.times { @answers << Lunixi::TransportError.new('timeout') }
    error = assert_raises(Lunixi::PhysicalPosOutcomeUnknownError) { @pos.create_payment(sale, idempotency_key: KEY) }
    assert_equal [KEY, 3, 0], [error.idempotency_key, error.attempts, error.status]
    assert_equal 3, gateway_calls.size
  end

  def test_uncertain_5xx_followed_by_a_4xx_stays_unknown
    @answers << failure(500, 'internal_error')
    @answers << failure(409, 'physical_pos.idempotency_mismatch')
    error = assert_raises(Lunixi::PhysicalPosOutcomeUnknownError) { @pos.create_payment(sale, idempotency_key: KEY) }
    assert_equal [409, 'physical_pos.idempotency_mismatch', 2], [error.status, error.code, error.attempts]
    assert_equal 2, gateway_calls.size
  end

  def test_a_2xx_without_a_payment_is_uncertain
    @answers << response(202, { 'data' => { 'replayed' => false } })
    @answers << response(202, { 'data' => { 'payment' => { 'paymentId' => '' } } })
    @answers << response(202, { 'data' => { 'payment' => payment('amountMinor' => 4500) } })
    assert_raises(Lunixi::PhysicalPosOutcomeUnknownError) { @pos.create_payment(sale, idempotency_key: KEY) }
    assert_equal 3, gateway_calls.size
  end

  def test_not_started_5xx_is_retried_and_then_raised_as_is
    3.times { @answers << failure(503, 'physical_pos.service.busy') }
    error = assert_raises(Lunixi::ApiError) { @pos.create_payment(sale, idempotency_key: KEY) }
    refute_kind_of Lunixi::PhysicalPosOutcomeUnknownError, error
    assert_equal [503, 'physical_pos.service.busy', KEY], [error.status, error.code, error.idempotency_key]
    assert_equal 3, gateway_calls.size
  end

  def test_not_started_5xx_then_success
    @answers << failure(503, 'physical_pos.presence.unavailable')
    assert_equal 202, @pos.create_payment(sale, idempotency_key: KEY).status_code
    assert_equal 2, gateway_calls.size
  end

  def test_a_definite_4xx_stops_at_once
    @answers << failure(409, 'physical_pos.payment.previous_outcome_unknown')
    error = assert_raises(Lunixi::ApiError) { @pos.create_payment(sale, idempotency_key: KEY) }
    refute_kind_of Lunixi::PhysicalPosOutcomeUnknownError, error
    assert_equal ['physical_pos.payment.previous_outcome_unknown', KEY], [error.code, error.idempotency_key]
    assert_equal 1, gateway_calls.size
  end

  def test_rate_limit_is_typed_with_retry_after
    @answers << failure(429, 'RATE_LIMITED', { 'retry-after' => '7' })
    error = assert_raises(Lunixi::PhysicalPosRateLimitError) { @pos.create_payment(sale, idempotency_key: KEY) }
    assert_equal [7, KEY], [error.retry_after, error.idempotency_key]
    @answers << failure(429, 'RATE_LIMITED', {}, { 'retryAfterSeconds' => 3 })
    assert_equal 3, assert_raises(Lunixi::PhysicalPosRateLimitError) { @pos.create_payment(sale, idempotency_key: KEY) }.retry_after
    assert_equal 2, gateway_calls.size
  end

  def test_void_after_settlement_is_typed
    @answers << failure(409, 'physical_pos.payment.void_after_settlement', {}, { 'allowedOperation' => 'REFUND' })
    error = assert_raises(Lunixi::PhysicalPosVoidAfterSettlementError) do
      @pos.create_reversal(PAYMENT_ID, { operation: 'VOID', currency: 'TRY' }, idempotency_key: KEY)
    end
    assert_equal ['REFUND', KEY], [error.allowed_operation, error.idempotency_key]
  end

  # ── Reversal and cancel ──────────────────────────────────────────────────

  def test_create_reversal_by_items
    result = @pos.create_reversal(PAYMENT_ID, { operation: 'REFUND', currency: 'TRY', items: [{ lineNo: 1, quantityMilli: 1000 }] },
                                  idempotency_key: KEY)
    sent = gateway_calls.last
    assert_equal ['POST', "#{BASE}/payments/#{PAYMENT_ID}/reversals", KEY], [sent[:method], sent[:uri].path, sent[:headers]['Idempotency-Key']]
    assert_equal({ 'operation' => 'REFUND', 'currency' => 'TRY', 'items' => [{ 'lineNo' => 1, 'quantityMilli' => 1000 }] }, JSON.parse(sent[:body]))
    assert_equal 202, result.status_code
  end

  def test_cancel_payment_generates_a_key_and_returns_ok
    @answers << accepted(replayed: true)
    result = @pos.cancel_payment(PAYMENT_ID)
    sent = gateway_calls.last
    assert_equal ["#{BASE}/payments/#{PAYMENT_ID}/cancel", '{}'], [sent[:uri].path, sent[:body]]
    assert_match(/\A\h{8}-\h{4}-4\h{3}-[89ab]\h{3}-\h{12}\z/, sent[:headers]['Idempotency-Key'])
    assert_equal [sent[:headers]['Idempotency-Key'], 200], [result.idempotency_key, result.status_code]
    @pos.cancel_payment(PAYMENT_ID, idempotency_key: KEY)
    assert_equal KEY, gateway_calls.last[:headers]['Idempotency-Key']
    assert_nothing_sent { assert_raises(Lunixi::ConfigurationError) { @pos.cancel_payment(PAYMENT_ID, idempotency_key: '') } }
  end
end
