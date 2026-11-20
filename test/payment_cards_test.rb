# frozen_string_literal: true

require_relative 'test_helper'

class PaymentCardsTest < Minitest::Test
  PAN = '4111111111111111'
  CARD = { cardHolderName: 'Test Buyer', cardNumber: PAN, expireMonth: '12', expireYear: '2030', cvc: '123' }.freeze

  def setup
    @transport = RecordingTransport.new { response(200, { 'data' => {} }) }
    @sdk = client(transport: @transport)
  end

  def gateway_calls
    @transport.calls.reject { |request| request[:uri].path == '/api/v1/auth/token' }
  end

  def last_body
    JSON.parse(@transport.calls.last[:body])
  end

  def marketplace_body
    { amount: '10000', currency: 'TRY', orderId: 'order_1', callbackUrl: 'https://merchant.example/return',
      sellers: [{ subDealerId: 'seller_1', amountMinor: '6000' }, { subDealerId: 'seller_2', amountMinor: '4000', scenario: 'PRODUCT' }],
      multiSellerPolicy: 'ALL_OR_NOTHING', basketItems: [basket_item('10000')] }.merge(order_details)
  end

  def test_bin_info_posts_the_bin_without_a_signature
    @sdk.payments.bin_info('45438800')
    request = @transport.calls.last
    assert_equal ['POST', '/api/v1/bin/info'], [request[:method], request[:uri].path]
    assert_equal '{"binOrPan":"45438800"}', request[:body]
    refute request[:headers].key?('X-Signature')
    assert request[:headers].key?('Authorization')
  end

  def test_bin_info_rejects_malformed_input_without_echoing_it
    ['4543', '4543 8800', "#{PAN}000000", 45_438_800, nil].each do |value|
      error = assert_raises(Lunixi::ConfigurationError) { @sdk.payments.bin_info(value) }
      refute_includes error.message, '4543'
    end
    assert_empty gateway_calls
  end

  def test_installment_options_sends_enabled_installments_in_ascending_order
    request = Lunixi::InstallmentOptionsRequest.new('10000', 'try').with_bin_or_pan('45438800').with_enabled_installments([3, 1, 2])
    refute_includes request.inspect, '45438800'
    @sdk.payments.installment_options(request)
    sent = @transport.calls.last
    assert_equal '/api/v1/bin/installments', sent[:uri].path
    assert_equal '{"amount":"10000","currency":"TRY","binOrPan":"45438800","enabledInstallments":[1,2,3]}', sent[:body]
    refute sent[:headers].key?('X-Signature')

    @sdk.payments.installment_options(amount: '10000', currency: 'TRY', enabledInstallments: [6, 1])
    assert_equal [1, 6], last_body['enabledInstallments']
  end

  def test_installment_options_apply_the_intent_installment_rule
    calls = gateway_calls.size
    [[], [2, 3], [1, 1, 2], [0, 1], [1, 37], [1, '2'], '1,2', nil].each do |counts|
      assert_raises(Lunixi::ConfigurationError) do
        @sdk.payments.installment_options(amount: '10000', currency: 'TRY', enabledInstallments: counts)
      end
      assert_raises(Lunixi::ConfigurationError) do
        @sdk.payments.create_intent(payment_body.merge(enabledInstallments: counts), idempotency_key: idempotency_key)
      end
    end
    assert_raises(Lunixi::ConfigurationError) { @sdk.payments.installment_options(currency: 'TRY') }
    assert_raises(Lunixi::ConfigurationError) { @sdk.payments.installment_options(amount: 10_000, currency: 'TRY') }
    assert_raises(Lunixi::ConfigurationError) { @sdk.payments.installment_options(amount: '10000', currency: 'TRY', installment: 37) }
    assert_equal calls, gateway_calls.size

    @sdk.payments.create_intent(payment_body.merge(enabledInstallments: [3, 1]), idempotency_key: idempotency_key)
    assert_equal [1, 3], last_body['enabledInstallments']
  end

  def test_card_taxonomy
    @sdk.payments.card_taxonomy
    request = @transport.calls.last
    assert_equal ['GET', '/api/v1/bin/card-taxonomy'], [request[:method], request[:uri].path]
    assert_nil request[:body]
  end

  def test_store_card_is_signed_and_requires_an_idempotency_key
    request = Lunixi::StoreCardRequest.new(CARD, 'card_user_1', 'https://merchant.example/cards/return').with_currency('try')
                                     .with_buyer(order_details[:buyer]).with_billing_address(order_details[:billingAddress])
    refute_includes request.inspect, PAN
    @sdk.payments.store_card(request, idempotency_key: idempotency_key)
    sent = @transport.calls.last
    assert_equal ['POST', '/api/v1/payments/cards'], [sent[:method], sent[:uri].path]
    assert_equal %w[card cardUserKey callbackUrl currency buyer billingAddress], JSON.parse(sent[:body]).keys
    assert_equal idempotency_key, sent[:headers]['Idempotency-Key']
    assert sent[:headers].key?('X-Signature')
  end

  def test_store_card_local_errors_send_nothing_and_never_echo_the_card
    calls = gateway_calls.size
    error = assert_raises(Lunixi::ConfigurationError) do
      @sdk.payments.store_card({ card: CARD, cardUserKey: 'card_user_1', callbackUrl: 'https://merchant.example/r' }.merge(order_details))
    end
    refute_includes error.message, PAN
    error = assert_raises(Lunixi::ConfigurationError) do
      @sdk.payments.store_card({ card: CARD, cardUserKey: 'card_user_1', callbackUrl: 'https://merchant.example/r' }, idempotency_key: idempotency_key)
    end
    assert_equal 'Storing a card requires the order details: buyer, billingAddress.', error.message
    [{ card: CARD, callbackUrl: 'https://merchant.example/r' },
     { card: CARD, cardUserKey: 'card_user_1', callbackUrl: 'http://merchant.example/r' },
     { card: {}, cardUserKey: 'card_user_1', callbackUrl: 'https://merchant.example/r' }].each do |body|
      error = assert_raises(Lunixi::ConfigurationError) { @sdk.payments.store_card(body, idempotency_key: idempotency_key) }
      refute_includes error.message, PAN
    end
    assert_equal calls, gateway_calls.size
  end

  def test_stored_card_list_get_and_deactivate
    @sdk.payments.list_stored_cards('card_user_1')
    list = @transport.calls.last
    assert_equal ['GET', '/api/v1/payments/cards', 'cardUserKey=card_user_1'], [list[:method], list[:uri].path, list[:uri].query]
    refute list[:headers].key?('X-Signature')

    @sdk.payments.get_stored_card('sct_1')
    assert_equal '/api/v1/payments/cards/sct_1', @transport.calls.last[:uri].path

    @sdk.payments.deactivate_stored_card('sct_1', idempotency_key: idempotency_key)
    deactivate = @transport.calls.last
    assert_equal ['DELETE', '/api/v1/payments/cards/sct_1'], [deactivate[:method], deactivate[:uri].path]
    assert_equal idempotency_key, deactivate[:headers]['Idempotency-Key']
    assert deactivate[:headers].key?('X-Signature')

    calls = gateway_calls.size
    assert_raises(Lunixi::ConfigurationError) { @sdk.payments.deactivate_stored_card('sct_1') }
    assert_raises(Lunixi::ConfigurationError) { @sdk.payments.get_stored_card('../sct_1') }
    assert_raises(Lunixi::ConfigurationError) { @sdk.payments.list_stored_cards('') }
    assert_equal calls, gateway_calls.size
  end

  def test_marketplace_intent_is_signed_and_keyed
    @sdk.payments.create_marketplace_intent(marketplace_body, idempotency_key: idempotency_key)
    sent = @transport.calls.last
    assert_equal ['POST', '/api/v1/payments/marketplace/intents'], [sent[:method], sent[:uri].path]
    assert_equal(%w[6000 4000], JSON.parse(sent[:body])['sellers'].map { |seller| seller['amountMinor'] })
    assert_equal idempotency_key, sent[:headers]['Idempotency-Key']
    assert sent[:headers].key?('X-Signature')
  end

  def test_marketplace_intent_total_and_amount_rules
    calls = gateway_calls.size
    mismatch = marketplace_body.merge(sellers: [{ subDealerId: 'seller_1', amountMinor: '6000' }, { subDealerId: 'seller_2', amountMinor: '3999' }])
    [mismatch,
     marketplace_body.merge(sellers: []),
     marketplace_body.merge(sellers: [{ subDealerId: 'seller_1', amountMinor: 10_000 }]),
     marketplace_body.merge(sellers: [{ amountMinor: '10000' }]),
     marketplace_body.merge(price: '10000'),
     marketplace_body.merge(amount: '0')].each do |body|
      assert_raises(Lunixi::ConfigurationError) { @sdk.payments.create_marketplace_intent(body, idempotency_key: idempotency_key) }
    end
    assert_raises(Lunixi::ConfigurationError) { @sdk.payments.create_marketplace_intent(marketplace_body, idempotency_key: 'short') }
    error = assert_raises(Lunixi::ConfigurationError) do
      @sdk.payments.create_marketplace_intent(marketplace_body.except(:billingAddress), idempotency_key: idempotency_key)
    end
    assert_equal 'A marketplace payment intent requires the order details: billingAddress.', error.message
    assert_equal calls, gateway_calls.size

    buyer = order_details[:buyer].except(:ip)
    @sdk.payments.create_marketplace_intent(marketplace_body.merge(buyer: buyer), idempotency_key: idempotency_key)
    refute last_body['buyer'].key?('ip')
  end

  def test_analytics_routes
    @sdk.payments.failover_recovery_analytics(from: '2026-11-01', to: '2026-11-15')
    failover = @transport.calls.last
    assert_equal ['GET', '/api/v1/payments/analytics/failover-recovery', 'from=2026-11-01&to=2026-11-15'],
                 [failover[:method], failover[:uri].path, failover[:uri].query]
    @sdk.payments.provider_credential_analytics('cred_1', range: '7d')
    credential = @transport.calls.last
    assert_equal ['/api/v1/payments/analytics/provider-credentials/cred_1', 'range=7d'], [credential[:uri].path, credential[:uri].query]
    assert_raises(Lunixi::ConfigurationError) { @sdk.payments.provider_credential_analytics('cred/1') }
  end
end
