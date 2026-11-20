# frozen_string_literal: true

require_relative 'test_helper'

# Wallet calls go through WALLET_ROUTES: path, method, body and key rule are checked before sending.
# Ids and values are synthetic.
class WalletTest < Minitest::Test
  END_USER = '0d8f6b1c-1111-4222-8333-444455556666'
  ACCOUNT = '0d8f6b1c-2222-4222-8333-444455556666'
  OPERATION = '0d8f6b1c-3333-4222-8333-444455556666'
  KEY = 'wallet-key-1'

  def setup
    @transport = RecordingTransport.new { response(200, { 'data' => { 'ok' => true } }) }
    @wallet = client(transport: @transport).wallet
  end

  def test_create_end_user_is_signed_with_the_key_and_the_body
    result = @wallet.end_users.create({ programId: 'prog_1', account_type: 'PERSONAL', phone: '+905550000000' }, idempotency_key: " #{KEY} ")
    call = api_calls(@transport).fetch(0)
    assert_equal({ 'ok' => true }, result)
    assert_equal ['POST', '/api/v1/wallet/end-users'], [call[:method], call[:uri].path]
    assert_equal({ 'programId' => 'prog_1', 'accountType' => 'PERSONAL', 'phone' => '+905550000000' }, sent_json(call))
    assert_equal KEY, call[:headers]['Idempotency-Key']
    assert call[:headers].key?('X-Signature')
  end

  def test_card_topup_requires_the_buyer_and_billing_address
    details = order_details
    request = { creditWalletAccountId: ACCOUNT, amount: '12550', currency: 'TRY' }
    error = assert_raises(Lunixi::ConfigurationError) { @wallet.topups.start_card(request, idempotency_key: KEY) }
    assert_equal 'startCardTopup requires buyer, billingAddress.', error.message
    error = assert_raises(Lunixi::ConfigurationError) do
      @wallet.topups.start_card(request.merge(buyer: details[:buyer].except(:ip), billing_address: details[:billingAddress]), idempotency_key: KEY)
    end
    assert_equal 'A wallet card top-up requires the order details: buyer.ip.', error.message
    assert_empty api_calls(@transport)

    @wallet.topups.start_card(request.merge(buyer: details[:buyer], billingAddress: details[:billingAddress]), idempotency_key: KEY)
    call = api_calls(@transport).fetch(0)
    assert_equal ['POST', '/api/v1/wallet/topups/card'], [call[:method], call[:uri].path]
    assert_equal %w[creditWalletAccountId amount currency buyer billingAddress], sent_json(call).keys
  end

  def test_reads_are_signed_and_filters_are_checked
    @wallet.end_users.list(programId: 'prog_1', limit: 20)
    call = api_calls(@transport).fetch(0)
    assert_equal '/api/v1/wallet/end-users', call[:uri].path
    assert_equal 'programId=prog_1&limit=20', call[:uri].query
    assert call[:headers].key?('X-Signature')
    assert_raises(Lunixi::ConfigurationError) { @wallet.end_users.list(sort: 'name') }
  end

  def test_local_errors_send_nothing
    assert_raises(Lunixi::ConfigurationError) { @wallet.end_users.create({ programId: 'p', accountType: 'PERSONAL', phone: '1' }) }
    assert_raises(Lunixi::ConfigurationError) { @wallet.end_users.create({ programId: 'p', accountType: 'PERSONAL' }, idempotency_key: KEY) }
    assert_raises(Lunixi::ConfigurationError) do
      @wallet.end_users.create({ programId: 'p', accountType: 'PERSONAL', phone: '1', merchantId: 'm' }, idempotency_key: KEY)
    end
    assert_raises(Lunixi::ConfigurationError) { @wallet.transfers.quote_w2w(transfer(amount: 12_550)) }
    assert_raises(Lunixi::ConfigurationError) { @wallet.transfers.quote_w2w(transfer(amount: '125.50')) }
    assert_raises(Lunixi::ConfigurationError) { @wallet.transfers.quote_w2w(transfer(amount: '0')) }
    assert_raises(Lunixi::ConfigurationError) { @wallet.topups.refund(OPERATION, { reason: 'r', requesterPrincipal: 'a' }) }
    assert_raises(Lunixi::ConfigurationError) { @wallet.qr.revoke('') }
    assert_raises(Lunixi::ConfigurationError) { @wallet.end_users.freeze_end_user(END_USER, idempotency_key: "bad\nkey") }
    assert_raises(Lunixi::ConfigurationError) { @wallet.end_users.freeze_end_user(END_USER, idempotency_key: 'k' * 129) }
    assert_empty api_calls(@transport)
  end

  def test_a_route_without_a_key_refuses_one
    invoker = Lunixi::WalletInvoker.new(client(transport: @transport))
    assert_raises(Lunixi::ConfigurationError) { invoker.call('lookupWallet', body: { 'phone' => '1' }, idempotency_key: KEY) }
    assert_empty api_calls(@transport)
  end

  def test_short_wallet_keys_are_accepted
    @wallet.end_users.freeze_end_user(END_USER, reason: 'fraud check', idempotency_key: 'k1')
    call = api_calls(@transport).fetch(0)
    assert_equal "/api/v1/wallet/end-users/#{END_USER}/freeze", call[:uri].path
    assert_equal 'k1', call[:headers]['Idempotency-Key']
    assert_equal({ 'reason' => 'fraud check' }, sent_json(call))
  end

  def test_complete_puts_the_operation_id_in_the_body
    @wallet.transfers.complete_w2w(OPERATION, { endUserId: END_USER, integrityHash: 'h', nonce: 'n', otpCode: '123456' }, idempotency_key: KEY)
    call = api_calls(@transport).fetch(0)
    assert_equal "/api/v1/wallet/transfers/w2w/#{OPERATION}/complete", call[:uri].path
    assert_equal OPERATION, sent_json(call)['operationId']
    assert_raises(Lunixi::ConfigurationError) do
      @wallet.withdrawals.complete(OPERATION, { endUserId: END_USER, operationId: 'other', integrityHash: 'h', nonce: 'n' }, idempotency_key: KEY)
    end
  end

  def test_initiate_iban_transfer
    @wallet.transfers.initiate_w2_iban(transfer(amount: '12550').merge(beneficiaryName: 'Test Person', iban: 'TR000000000000000000000000'),
                                       idempotency_key: KEY)
    call = api_calls(@transport).fetch(0)
    assert_equal '/api/v1/wallet/transfers/w2iban', call[:uri].path
    assert_equal '12550', sent_json(call)['amount']
  end

  def test_bulk_payout_items_are_checked_row_by_row
    base = { programId: 'prog_1', sourceWalletAccountId: ACCOUNT, currency: 'TRY' }
    @wallet.bulk_payouts.create(base.merge(items: [{ targetType: 'WALLET', targetRef: 'W1', amount: '100' }]), idempotency_key: KEY)
    assert_equal [{ 'targetType' => 'WALLET', 'targetRef' => 'W1', 'amount' => '100' }], sent_json(api_calls(@transport).fetch(0))['items']
    assert_raises(Lunixi::ConfigurationError) { @wallet.bulk_payouts.create(base.merge(items: []), idempotency_key: KEY) }
    assert_raises(Lunixi::ConfigurationError) do
      @wallet.bulk_payouts.create(base.merge(items: [{ targetType: 'WALLET', targetRef: 'W1', amount: 100 }]), idempotency_key: KEY)
    end
    assert_raises(Lunixi::ConfigurationError) do
      @wallet.corporate.import_employees('corp_1', [{ phone: '1', iban: 'x' }], idempotency_key: KEY)
    end
  end

  def test_qr_image_is_bytes
    transport = RecordingTransport.new { response(200, '<svg/>', 'content-type' => 'image/svg+xml') }
    image = client(transport: transport).wallet.qr.image('qr_1', format: 'svg', scale: 4)
    call = api_calls(transport).fetch(0)
    assert_equal '<svg/>', image
    assert_equal 'format=svg&scale=4', call[:uri].query
    assert_match(%r{image/svg\+xml}, call[:headers]['Accept'])
    assert_raises(Lunixi::ConfigurationError) { @wallet.qr.image('qr_1', format: 'gif') }
    assert_raises(Lunixi::ConfigurationError) { @wallet.qr.image('qr_1', scale: 21) }
  end

  def test_lists_are_pages
    transport = RecordingTransport.new do
      response(200, { 'data' => { 'operations' => [{ 'operationId' => OPERATION }], 'nextCursor' => 'c2' } })
    end
    page = client(transport: transport).wallet.operations.list(endUserId: END_USER)
    assert_equal [{ 'operationId' => OPERATION }], page.items
    assert_equal 'c2', page.next_cursor
    assert page.has_more?
  end

  def test_freeze_does_not_replace_object_freeze
    resource = @wallet.end_users
    assert_same resource, resource.freeze
    assert resource.frozen?
    assert_empty api_calls(@transport)
  end

  private

  def transfer(amount:)
    { endUserId: END_USER, sourceWalletAccountId: ACCOUNT, amount: amount, currency: 'TRY' }
  end
end
