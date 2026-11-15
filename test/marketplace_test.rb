# frozen_string_literal: true

require_relative 'test_helper'

# Marketplace split charges are signed; dealer, commission, payout and audit routes carry the access
# token only. The card number, names and ids are synthetic test values.
class MarketplaceTest < Minitest::Test
  TEST_CARD_NUMBER = '5400000000000004'

  def setup
    @answer = { 'success' => true, 'paymentId' => 'pi_1', 'token' => 'tok_1', 'checkoutFormContent' => '<div></div>' }
    @transport = RecordingTransport.new { response(200, @answer) }
    @marketplace = client(transport: @transport).marketplace
  end

  def legs
    [{ subDealerId: 'd_alice', amountMinor: '60000' }, { sub_dealer_id: 'd_bob', amount_minor: '40000', scenario: { type: 'DYNAMIC_RATE' } }]
  end

  def charge_request(amount = '100000')
    { amount: amount, currency: 'TRY', orderId: 'ORD-MP-1',
      card: { cardHolderName: 'Test Buyer', cardNumber: TEST_CARD_NUMBER, expireMonth: '12', expireYear: '30', cvcNumber: '123' },
      buyer: { name: 'Test', surname: 'Buyer' }, billingAddress: { city: 'Istanbul' },
      basketItems: [{ id: 'SKU-1', name: 'Item', category1: 'Demo', itemType: 'PHYSICAL', price: amount }] }
  end

  def test_only_the_split_charges_are_signed
    Lunixi::MARKETPLACE_ROUTES.each do |name, route|
      split = route['path'].start_with?('/api/v1/payments/marketplace/')
      assert_equal split, route['stepUp'], name
      assert_match %r{\A/api/v1/marketplace/}, route['path'], name unless split
    end
  end

  def test_create_checkout_intent_sends_the_signed_split
    intent = @marketplace.create_checkout_intent({ amount: '100000', currency: 'TRY', orderId: 'WC-7' }, legs,
                                                 idempotency_key: idempotency_key)
    assert_equal 'tok_1', intent['token']
    call = api_calls(@transport).fetch(0)
    assert_equal ['POST', '/api/v1/payments/marketplace/intents'], [call[:method], call[:uri].path]
    assert call[:headers].key?('X-Signature')
    assert_equal idempotency_key, call[:headers]['Idempotency-Key']
    body = sent_json(call)
    assert_equal 'ALL_OR_NOTHING', body['multiSellerPolicy']
    assert_equal [{ 'subDealerId' => 'd_alice', 'amountMinor' => '60000' },
                  { 'subDealerId' => 'd_bob', 'amountMinor' => '40000', 'scenario' => { 'type' => 'DYNAMIC_RATE' } }], body['sellers']
  end

  def test_an_intent_without_a_token_raises
    @answer = { 'success' => false, 'code' => 'marketplace.payment.seller_not_eligible', 'message' => 'seller not eligible' }
    error = assert_raises(Lunixi::ApiError) do
      @marketplace.create_checkout_intent({ amount: '1000', currency: 'TRY', orderId: 'o_1' }, [{ subDealerId: 'd_1', amountMinor: '1000' }])
    end
    assert_equal 'marketplace.payment.seller_not_eligible', error.code
  end

  def test_seller_legs_are_checked_before_sending
    intent = { amount: '1000', currency: 'TRY', orderId: 'o_1' }
    [
      -> { @marketplace.create_checkout_intent(intent, []) },
      -> { @marketplace.create_checkout_intent(intent, [{ subDealerId: 'd_1', amountMinor: '0' }, { subDealerId: 'd_2', amountMinor: '1000' }]) },
      -> { @marketplace.create_checkout_intent(intent, [{ subDealerId: 'd_1', amountMinor: 1000 }]) },
      -> { @marketplace.create_checkout_intent(intent, [{ subDealerId: 'd_1', amountMinor: '1000', iban: 'TR00' }]) },
      -> { @marketplace.create_checkout_intent(intent, [{ amountMinor: '1000' }]) },
      -> { @marketplace.create_checkout_intent(intent, [{ subDealerId: 'd_1', amountMinor: '1000' }], multi_seller_policy: 'SOME') },
      -> { @marketplace.create_checkout_intent(intent.merge(sellers: []), [{ subDealerId: 'd_1', amountMinor: '1000' }]) },
      -> { @marketplace.create_checkout_intent(intent.merge(price: '1000'), [{ subDealerId: 'd_1', amountMinor: '1000' }]) }
    ].each { |call| assert_raises(Lunixi::ConfigurationError) { call.call } }
    error = assert_raises(Lunixi::ConfigurationError) { @marketplace.create_checkout_intent(intent, [{ subDealerId: 'd_1', amountMinor: '999' }]) }
    assert_match(/add up to 999/, error.message)
    assert_empty api_calls(@transport)
  end

  def test_card_charges_go_to_the_2d_and_3d_routes
    @answer = { 'status' => 'success', 'data' => { 'paymentId' => 'pay_1', 'status' => 'SUCCEEDED' } }
    @marketplace.charge_marketplace_card2d(charge_request, legs, multi_seller_policy: Lunixi::MarketplaceMultiSellerPolicy::PARTIAL_ALLOWED,
                                                                 idempotency_key: idempotency_key)
    @marketplace.charge_marketplace_card3d(charge_request.merge(callbackUrl: 'https://merchant.example/3ds'), legs)
    two_d, three_d = api_calls(@transport)
    assert_equal '/api/v1/payments/marketplace/2d', two_d[:uri].path
    assert_equal '/api/v1/payments/marketplace/3d', three_d[:uri].path
    assert two_d[:headers].key?('X-Signature')
    assert_equal idempotency_key, two_d[:headers]['Idempotency-Key']
    refute three_d[:headers].key?('Idempotency-Key')
    body = sent_json(two_d)
    assert_equal 'PARTIAL_ALLOWED', body['multiSellerPolicy']
    assert_equal 2, body['sellers'].size
    assert_equal TEST_CARD_NUMBER, body['card']['cardNumber']
  end

  def test_charge_errors_never_carry_card_data
    [
      -> { @marketplace.charge_marketplace_card2d(charge_request.except(:buyer), legs) },
      -> { @marketplace.charge_marketplace_card2d(charge_request.merge(basketItems: []), legs) },
      -> { @marketplace.charge_marketplace_card2d(charge_request.merge(amount: 100_000), legs) },
      -> { @marketplace.charge_marketplace_card2d(charge_request.merge(preauth: 'yes'), legs) },
      -> { @marketplace.charge_marketplace_card2d(charge_request('90000'), legs) },
      -> { @marketplace.charge_marketplace_card(charge_request.merge(paidPrice: '100000')) }
    ].each do |call|
      error = assert_raises(Lunixi::ConfigurationError) { call.call }
      refute_includes error.message, TEST_CARD_NUMBER
      refute_includes error.message, '123'
    end
    assert_empty api_calls(@transport)
  end

  def test_dealer_lifecycle
    @answer = { 'success' => true, 'data' => { 'id' => 'd_1', 'status' => 'DRAFT' } }
    @marketplace.create_dealer({ legalName: 'Test Dealer Ltd', dealer_type: 'LEGAL_ENTITY', taxId: '0000000000' })
    @marketplace.update_dealer_status('d_1', Lunixi::MarketplaceDealerStatus::SUSPENDED)
    @answer = { 'success' => true, 'token' => 'onb_1', 'data' => { 'expiresAt' => '2026-12-01T00:00:00Z' } }
    link = @marketplace.onboarding_token('d_1')
    assert_equal 'https://altbayi.lunixi.com/m/onb_1', Lunixi::Marketplace.onboarding_url(link)
    assert_equal 'https://dealer.example/x', Lunixi::Marketplace.onboarding_url({ 'url' => 'https://dealer.example/x', 'token' => 'onb_1' })
    @marketplace.bulk_create_dealers([{ legalName: 'A' }, { legalName: 'B' }])
    create, status, token, bulk = api_calls(@transport)
    assert_equal({ 'legalName' => 'Test Dealer Ltd', 'dealerType' => 'LEGAL_ENTITY', 'taxId' => '0000000000' }, sent_json(create))
    refute create[:headers].key?('X-Signature')
    assert_equal ['PUT', '/api/v1/marketplace/dealers/d_1/status'], [status[:method], status[:uri].path]
    assert_equal({ 'status' => 'SUSPENDED' }, sent_json(status))
    assert_equal '/api/v1/marketplace/dealers/d_1/onboarding-token', token[:uri].path
    assert_equal({ 'dealers' => [{ 'legalName' => 'A' }, { 'legalName' => 'B' }] }, sent_json(bulk))
    [
      -> { @marketplace.create_dealer({ legalName: 'X', dealerType: 'PARTNERSHIP' }) },
      -> { @marketplace.create_dealer({ taxId: '0000000000' }) },
      -> { @marketplace.update_dealer_status('d_1', 'PAUSED') },
      -> { @marketplace.bulk_create_dealers([]) }
    ].each { |call| assert_raises(Lunixi::ConfigurationError) { call.call } }
    assert_equal 4, api_calls(@transport).size
  end

  def test_commissions_payouts_and_audit
    @answer = { 'success' => true, 'data' => { 'items' => [{ 'id' => 'po_1', 'amountMinor' => '1000' }] } }
    @marketplace.resolve_commission('d_1', category_code: 'ELECTRONICS', mtd_volume_minor: '500000')
    @marketplace.create_payout({ subDealerId: 'd_1', amountMinor: '1000', currency: 'TRY' })
    @marketplace.bulk_mark_payouts_paid(%w[po_1 po_2], { reference: 'BATCH-1' })
    page = @marketplace.payout_ledger(status: 'PENDING', limit: 10)
    @marketplace.verify_audit_log
    resolve, payout, bulk, ledger, verify = api_calls(@transport)
    assert_equal 'subDealerId=d_1&categoryCode=ELECTRONICS&mtdVolumeMinor=500000', resolve[:uri].query
    assert_equal '/api/v1/marketplace/payouts', payout[:uri].path
    assert_equal({ 'reference' => 'BATCH-1', 'payoutIds' => %w[po_1 po_2] }, sent_json(bulk))
    assert_equal 'status=PENDING&limit=10', ledger[:uri].query
    assert_equal '1000', page.items.first['amountMinor']
    assert_equal '/api/v1/marketplace/audit-log/verify', verify[:uri].path
    [
      -> { @marketplace.create_payout({ subDealerId: 'd_1', amountMinor: 1000 }) },
      -> { @marketplace.resolve_commission('d_1', mtd_volume_minor: 500_000) },
      -> { @marketplace.bulk_mark_payouts_paid([]) },
      -> { @marketplace.payout_ledger(from: '2026-01-01') }
    ].each { |call| assert_raises(Lunixi::ConfigurationError) { call.call } }
    assert_equal 5, api_calls(@transport).size
  end

  def test_an_answer_with_a_numeric_amount_is_refused
    @answer = { 'success' => true, 'data' => { 'items' => [{ 'id' => 'po_1', 'payoutAmountMinor' => 1000 }] } }
    assert_raises(Lunixi::ConfigurationError) { @marketplace.payout_ledger }
  end
end
