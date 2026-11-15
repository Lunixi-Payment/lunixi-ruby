# frozen_string_literal: true

require_relative 'test_helper'

# Physical POS payments: request bodies, the Idempotency-Key rule, 202 / 200, the attempt loop of the
# payment writes (an uncertain outcome is never lost), card-data refusal and filters. Ids and values
# are synthetic.
class PhysicalPosPaymentsTest < Minitest::Test
  PAYMENT_ID = '0192f3a1-0000-7000-8000-000000000001'
  DEVICE_ID = '5f0c2b1e-1111-4222-8333-444455556666'
  KEY = 'pos-payment-key-0001'
  BASE = '/api/v1/physical-pos'

  def setup
    @answers = []
    @transport = RecordingTransport.new { |request| next_answer(request) }
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
      assert_raises(Lunixi::ConfigurationError) { @pos.create_payment(sale.reject { |key, _| key == :target }, idempotency_key: KEY) }
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
    assert_equal [KEY, KEY], calls.map { |call| call[:headers]['Idempotency-Key'] }
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

  def test_cancel_payment_generates_a_key_and_is_200
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

  # ── Reads ────────────────────────────────────────────────────────────────

  def test_reads_unwrap_and_check_money
    @answers << response(200, { 'data' => { 'payment' => payment } })
    assert_equal PAYMENT_ID, @pos.get_payment(PAYMENT_ID)['paymentId']
    assert_equal "#{BASE}/payments/#{PAYMENT_ID}", gateway_calls.last[:uri].path
    assert gateway_calls.last[:headers].key?('X-Signature')
    @answers << response(200, { 'data' => { 'payment' => payment('amountMinor' => 4500) } })
    assert_raises(Lunixi::ConfigurationError) { @pos.get_payment(PAYMENT_ID) }
    @answers << response(200, { 'data' => { 'totals' => [{ 'difference' => { 'netMinor' => '-150', 'saleMinor' => '-10' } }] } })
    assert_equal '-10', @pos.get_sales_summary(dateFrom: '2026-11-01').dig('totals', 0, 'difference', 'saleMinor')
  end

  def test_lists_return_pages_and_check_filters
    @answers << response(200, { 'data' => { 'items' => [payment] }, 'pageInfo' => { 'hasMore' => true, 'nextCursor' => 'c_2' } })
    page = @pos.list_payments(deviceId: DEVICE_ID, limit: 20, createdFrom: Time.utc(2026, 11, 1, 9), merchant_reference: 'ORD-1')
    assert_equal [1, true, 'c_2', nil], [page.items.size, page.has_more, page.next_cursor, page.total_count]
    assert_equal({ 'limit' => '20', 'deviceId' => DEVICE_ID, 'createdFrom' => '2026-11-01T09:00:00.000Z', 'merchantReference' => 'ORD-1' },
                 URI.decode_www_form(gateway_calls.last[:uri].query).to_h)
    assert_nothing_sent do
      assert_raises(Lunixi::ConfigurationError) { @pos.list_payments(status: 'APPROVED') }
      assert_raises(Lunixi::ConfigurationError) { @pos.list_payments(limit: 101) }
      assert_raises(Lunixi::ConfigurationError) { @pos.list_payments(limit: '20') }
      assert_raises(Lunixi::ConfigurationError) { @pos.list_transactions(amountFromMinor: 100) }
      assert_raises(Lunixi::ConfigurationError) { @pos.list_settlement_runs(includeTotal: 'true') }
      assert_raises(Lunixi::ConfigurationError) { @pos.get_tax_summary(groupBy: 'DAY') }
    end
  end

  def test_report_days_and_amount_filters
    @answers << response(200, { 'data' => {} })
    @pos.get_sales_summary(dateFrom: Date.new(2026, 11, 1), dateTo: '2026-11-07', groupBy: 'DAY', storeId: '')
    assert_equal({ 'dateFrom' => '2026-11-01', 'dateTo' => '2026-11-07', 'groupBy' => 'DAY' }, URI.decode_www_form(gateway_calls.last[:uri].query).to_h)
    @answers << response(200, { 'data' => { 'items' => [] } })
    @pos.list_transactions(amountFromMinor: '100', amountToMinor: '5000', operation: 'REFUND')
    assert_equal "#{BASE}/transactions", gateway_calls.last[:uri].path
    assert_equal({ 'amountFromMinor' => '100', 'amountToMinor' => '5000', 'operation' => 'REFUND' }, URI.decode_www_form(gateway_calls.last[:uri].query).to_h)
  end

  def test_iterate_payments_walks_every_page
    @answers << response(200, { 'data' => { 'items' => [payment('paymentId' => 'p1')] }, 'pageInfo' => { 'hasMore' => true, 'nextCursor' => 'c_2' } })
    @answers << response(200, { 'data' => { 'items' => [payment('paymentId' => 'p2')] }, 'pageInfo' => { 'hasMore' => false } })
    assert_equal %w[p1 p2], @pos.iterate_payments(limit: 1).map { |entry| entry['paymentId'] }
    assert_equal ['limit=1', 'limit=1&cursor=c_2'], gateway_calls.map { |call| call[:uri].query }
  end

  # ── End-of-day ───────────────────────────────────────────────────────────

  def test_start_settlement_is_keyed_and_reports_202_or_200
    @answers << response(202, { 'data' => { 'run' => { 'runId' => 'run_1', 'runStatus' => 'PENDING' }, 'replayed' => false } })
    result = @pos.start_settlement(DEVICE_ID)
    sent = gateway_calls.last
    assert_equal ['POST', "#{BASE}/devices/#{DEVICE_ID}/settlement", '{}'], [sent[:method], sent[:uri].path, sent[:body]]
    assert_equal [sent[:headers]['Idempotency-Key'], 202, 'run_1'], [result.idempotency_key, result.status_code, result['run']['runId']]
    @answers << response(200, { 'data' => { 'run' => { 'runId' => 'run_1' }, 'replayed' => true } })
    replay = @pos.start_settlement(DEVICE_ID, idempotency_key: KEY)
    assert_equal [200, true], [replay.status_code, replay.replayed]
    assert_equal KEY, gateway_calls.last[:headers]['Idempotency-Key']
  end

  def test_settlement_reads
    @answers << response(200, { 'data' => { 'run' => { 'runId' => 'run_1' } } })
    assert_equal 'run_1', @pos.get_settlement_run('run_1')['runId']
    @answers << response(200, { 'data' => { 'items' => [{ 'lines' => [{ 'reported' => { 'saleMinor' => '100' } }] }] }, 'pageInfo' => { 'totalCount' => 1 } })
    assert_equal 1, @pos.list_settlements(deviceId: DEVICE_ID, lineStatus: 'MATCHED').items.size
    @answers << response(200, { 'data' => { 'items' => [] }, 'pageInfo' => { 'totalCount' => 4, 'hasMore' => false } })
    assert_equal 4, @pos.list_settlement_runs(includeTotal: true, source: 'SCHEDULED').total_count
    assert_equal 'includeTotal=true&source=SCHEDULED', gateway_calls.last[:uri].query
  end
end
