# frozen_string_literal: true

require_relative 'test_helper'

# Bank accounts, transfers and FX: filters and bodies are checked before sending; transfer and order
# writes carry a generated or given key and are retried with it. Ids and values are synthetic.
class BankConnectTest < Minitest::Test
  ACCOUNT = '0d8f6b1c-1111-4222-8333-444455556666'
  OTHER_ACCOUNT = '0d8f6b1c-2222-4222-8333-444455556666'
  UUID_V4 = /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/
  SECRET = 'whsec_synthetic_test_only'

  def setup
    @transport = RecordingTransport.new { response(200, page_body) }
    @bank = client(transport: @transport).bank_connect
  end

  def test_list_transactions_builds_the_query_and_signs
    page = @bank.list_transactions(accountId: [ACCOUNT, OTHER_ACCOUNT], canonical_type: %w[FEE TAX], direction: 'DEBIT',
                                   bookedFrom: '2026-10-01T00:00:00Z', bookedTo: Time.utc(2026, 10, 31), minAmountMinor: '0', limit: 50)
    call = api_calls(@transport).fetch(0)
    assert_equal '/api/v1/bank-connect/transactions', call[:uri].path
    query = URI.decode_www_form(call[:uri].query).to_h
    assert_equal "#{ACCOUNT},#{OTHER_ACCOUNT}", query['accountId']
    assert_equal 'FEE,TAX', query['canonicalType']
    assert_equal '2026-10-31T00:00:00.000Z', query['bookedTo']
    assert call[:headers].key?('X-Signature')
    assert_equal [{ 'transactionId' => 'tx_1' }], page.items
    assert_equal 'c2', page.next_cursor
    assert page.has_more?
  end

  def test_filter_rules_fail_before_sending
    [
      -> { @bank.list_banks(sort: 'name') },
      -> { @bank.list_banks(limit: 0) },
      -> { @bank.list_banks(limit: 101) },
      -> { @bank.list_accounts(status: 'DEGRADED') },
      -> { @bank.list_connections(status: %w[ACTIVE PAUSED]) },
      -> { @bank.list_balances(accountId: Array.new(101) { |index| "acc_#{index}" }) },
      -> { @bank.list_balances(accountId: 'a,b') },
      -> { @bank.list_transactions(minAmountMinor: 100) },
      -> { @bank.list_transactions(minAmountMinor: '10.5') },
      -> { @bank.list_transactions(minAmountMinor: '500', maxAmountMinor: '100') },
      -> { @bank.list_transactions(bookedTo: '2026-10-31T00:00:00Z') },
      -> { @bank.list_transactions(bookedFrom: '2026-10-31T00:00:00Z', bookedTo: '2026-10-01T00:00:00Z') },
      -> { @bank.list_transactions(bookedFrom: '2026-01-01T00:00:00Z', bookedTo: '2026-05-01T00:00:00Z') },
      -> { @bank.list_transactions(direction: 'IN') },
      -> { @bank.list_accounts(currency: 'TL') }
    ].each { |call| assert_raises(Lunixi::ConfigurationError) { call.call } }
    assert_empty api_calls(@transport)
  end

  def test_request_sync_posts_without_a_key
    @bank.request_sync(ACCOUNT)
    call = api_calls(@transport).fetch(0)
    assert_equal ['POST', "/api/v1/bank-connect/accounts/#{ACCOUNT}/sync"], [call[:method], call[:uri].path]
    refute call[:headers].key?('Idempotency-Key')
  end

  def test_transfer_create_generates_a_uuid_key
    @bank.transfers.create(transfer_request)
    call = api_calls(@transport).fetch(0)
    assert_equal ['POST', '/api/v1/bank-connect/transfers'], [call[:method], call[:uri].path]
    assert_match UUID_V4, call[:headers]['Idempotency-Key']
    assert_equal({ 'accountId' => ACCOUNT, 'receiverIban' => 'TR330006100519786457841326', 'receiverName' => 'Test Receiver',
                   'amountMinor' => '150075', 'currency' => 'TRY', 'description' => 'Invoice 42' }, sent_json(call))
  end

  def test_transfer_create_sends_the_given_key_and_checks_it
    @bank.transfers.create(transfer_request, idempotency_key: 'payout-0001')
    assert_equal 'payout-0001', api_calls(@transport).fetch(0)[:headers]['Idempotency-Key']
    assert_raises(Lunixi::ConfigurationError) { @bank.transfers.create(transfer_request, idempotency_key: 'short') }
    assert_raises(Lunixi::ConfigurationError) { @bank.transfers.create(transfer_request, idempotency_key: 'has a space') }
    assert_equal 1, api_calls(@transport).size
  end

  def test_transfer_body_rules
    [
      transfer_request.merge(amountMinor: 150_075),
      transfer_request.merge(amountMinor: '0'),
      transfer_request.merge(receiverName: 'A'),
      transfer_request.merge(receiverIban: "TR#{'0' * 41}"),
      transfer_request.merge(paymentPurpose: 'not valid!'),
      transfer_request.merge(description: 'x' * 141),
      transfer_request.merge(environment: 'LIVE'),
      transfer_request.reject { |key, _| key == :accountId }
    ].each { |request| assert_raises(Lunixi::ConfigurationError) { @bank.transfers.create(request) } }
    assert_empty api_calls(@transport)
  end

  def test_a_5xx_or_network_error_is_retried_with_the_same_key_and_body
    answers = [:network, response(500, { 'code' => 'INTERNAL' }), response(201, { 'data' => { 'transfer' => { 'id' => 'bt_1' } } })]
    transport = RecordingTransport.new do
      answer = answers.shift
      raise Lunixi::TransportError, 'down' if answer == :network

      answer
    end
    result = client(transport: transport).bank_connect.transfers.create(transfer_request)
    calls = api_calls(transport)
    assert_equal({ 'transfer' => { 'id' => 'bt_1' } }, result)
    assert_equal 3, calls.size
    assert_equal 1, calls.map { |call| call[:headers]['Idempotency-Key'] }.uniq.size
    assert_equal 1, calls.map { |call| call[:body] }.uniq.size
  end

  def test_a_4xx_is_not_retried_and_carries_the_key
    transport = RecordingTransport.new { response(409, { 'code' => 'bank_connect.transfer.idempotency_conflict' }) }
    error = assert_raises(Lunixi::ApiError) { client(transport: transport).bank_connect.transfers.create(transfer_request, idempotency_key: 'payout-0001') }
    assert_equal 1, api_calls(transport).size
    assert_equal 'payout-0001', error.idempotency_key
    assert_equal 'bank_connect.transfer.idempotency_conflict', error.code
  end

  def test_retries_stop_after_the_budget
    transport = RecordingTransport.new { response(503, { 'code' => 'UNAVAILABLE' }) }
    error = assert_raises(Lunixi::ApiError) { client(transport: transport, max_retries: 1).bank_connect.fx.create_order({ quoteId: 'q_1' }) }
    assert_equal 2, api_calls(transport).size
    assert_match UUID_V4, error.idempotency_key
  end

  def test_transfer_list_filters
    @bank.transfers.list(status: %w[SUBMITTED COMPLETED], createdFrom: Time.utc(2026, 10, 1), limit: 10)
    query = URI.decode_www_form(api_calls(@transport).fetch(0)[:uri].query).to_h
    assert_equal({ 'status' => 'SUBMITTED,COMPLETED', 'createdFrom' => '2026-10-01T00:00:00.000Z', 'limit' => '10' }, query)
    assert_raises(Lunixi::ConfigurationError) { @bank.transfers.list(status: 'DONE') }
    assert_raises(Lunixi::ConfigurationError) { @bank.fx.list_orders(status: 'PROCESSING') }
  end

  def test_fx_quote_takes_exactly_one_amount_and_two_accounts
    @bank.fx.create_quote(sourceAccountId: ACCOUNT, targetAccountId: OTHER_ACCOUNT, sourceAmountMinor: '10000')
    call = api_calls(@transport).fetch(0)
    assert_equal '/api/v1/bank-connect/fx/quotes', call[:uri].path
    refute call[:headers].key?('Idempotency-Key')
    base = { sourceAccountId: ACCOUNT, targetAccountId: OTHER_ACCOUNT }
    assert_raises(Lunixi::ConfigurationError) { @bank.fx.create_quote(base) }
    assert_raises(Lunixi::ConfigurationError) { @bank.fx.create_quote(base.merge(sourceAmountMinor: '1', targetAmountMinor: '1')) }
    assert_raises(Lunixi::ConfigurationError) { @bank.fx.create_quote(base.merge(targetAccountId: ACCOUNT, sourceAmountMinor: '1')) }
    assert_equal 1, api_calls(@transport).size
  end

  def test_transaction_webhook_is_read_after_the_signature
    data = { transactionId: 'tx_1', accountId: ACCOUNT, amountMinor: '2500', direction: 'CREDIT', extra: 'dropped' }
    body, headers = signed_webhook({ id: 'evt_1', type: Lunixi::BankConnectEvents::TRANSACTION_RECEIVED, environment: 'TEST', data: data }, SECRET)
    event = Lunixi::BankConnectWebhook.parse(body, headers, verifier)
    assert_equal ['evt_1', 'bank_account.transaction.received', 'TEST'], [event.id, event.type, event.environment]
    assert_equal '2500', event['amountMinor']
    assert_nil event['receiptNo']
    refute event.data.key?('extra')
    assert_equal Lunixi::BANK_ACCOUNT_TRANSACTION_RECEIVED_FIELDS, event.data.keys
  end

  def test_transfer_webhook_and_wrong_types
    body, headers = signed_webhook({ id: 'evt_1', type: Lunixi::BankTransferEvents::FAILED,
                                     data: { transferId: 'bt_1', amountMinor: '150075', failureCode: 'bank_connect.transfer.rejected' } }, SECRET)
    event = Lunixi::BankTransferWebhook.parse(body, headers, verifier)
    assert_equal 'bank_connect.transfer.rejected', event['failureCode']
    assert_raises(Lunixi::WebhookError) { Lunixi::BankConnectWebhook.parse(body, headers, verifier) }
    body, headers = signed_webhook({ id: 'evt_1', type: 'payment.bank_transfer.received', data: { amount: '1' } }, SECRET)
    assert_raises(Lunixi::WebhookError) { Lunixi::BankTransferWebhook.parse(body, headers, verifier) }
    body, headers = signed_webhook({ id: 'evt_1', type: Lunixi::BankTransferEvents::CREATED, data: { amountMinor: 150_075 } }, SECRET)
    assert_raises(Lunixi::WebhookError) { Lunixi::BankTransferWebhook.parse(body, headers, verifier) }
    assert_raises(Lunixi::WebhookError) { Lunixi::BankTransferWebhook.parse(body, headers.merge('X-Lunixi-Signature' => "v2=#{'0' * 64}"), verifier) }
  end

  private

  def verifier
    Lunixi::WebhookVerifier.new(secret: SECRET, clock: -> { NOW })
  end

  def page_body
    { 'data' => { 'items' => [{ 'transactionId' => 'tx_1' }] }, 'pageInfo' => { 'hasMore' => true, 'nextCursor' => 'c2', 'totalCount' => nil } }
  end

  def transfer_request
    { accountId: ACCOUNT, receiverIban: 'TR330006100519786457841326', receiverName: ' Test Receiver ', amountMinor: '150075',
      currency: 'try', description: 'Invoice 42' }
  end
end
