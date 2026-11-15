# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'physical_pos_payment_support'

# Physical POS reads, lists and their filters, and end-of-day settlement. Ids and values are synthetic.
class PhysicalPosReadsTest < Minitest::Test
  include PhysicalPosPaymentSupport

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
    assert_equal(%w[p1 p2], @pos.iterate_payments(limit: 1).map { |entry| entry['paymentId'] })
    assert_equal(['limit=1', 'limit=1&cursor=c_2'], gateway_calls.map { |call| call[:uri].query })
  end

  # ── End-of-day ───────────────────────────────────────────────────────────

  def test_start_settlement_is_keyed_and_reports_accepted_or_ok
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
