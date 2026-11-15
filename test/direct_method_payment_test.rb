# frozen_string_literal: true

require_relative 'test_helper'

class DirectMethodPaymentTest < Minitest::Test
  def setup
    @transport = RecordingTransport.new { response(202, { 'data' => { 'paymentId' => 'pay_1', 'status' => 'PENDING' } }) }
    @sdk = client(transport: @transport)
  end

  def bank_transfer_body
    { paymentMethod: 'BANK_TRANSFER', amount: '10000', currency: 'TRY', orderId: 'order_1', bankTransfer: { bankCode: '0062' } }
  end

  def wallet_body
    { paymentMethod: 'WALLET', amount: '10000', currency: 'TRY', orderId: 'order_1', wallet: { providerCode: 'wallet_a', gsmNumber: '+905321234567' } }
  end

  def pay(body, key = idempotency_key)
    @sdk.payments.direct_method_payment(body, idempotency_key: key)
  end

  def assert_rejected(body)
    assert_raises(Lunixi::ConfigurationError) { pay(body) }
  end

  def test_bank_transfer_request_builds_the_documented_body
    request = Lunixi::DirectMethodPaymentRequest.new('10000', 'TRY', 'order_1')
                                                .with_method_fields(Lunixi::PaymentMethod::BANK_TRANSFER, nil, bankCode: '0062')
    pay(request)
    sent = @transport.calls.last
    assert_equal '/api/v1/payments/direct/payment', sent[:uri].path
    assert_equal '{"paymentMethod":"BANK_TRANSFER","amount":"10000","currency":"TRY","orderId":"order_1","bankTransfer":{"bankCode":"0062"}}', sent[:body]
    refute_includes sent[:body], 'providerCode'
    assert_equal idempotency_key, sent[:headers]['Idempotency-Key']
    assert sent[:headers].key?('X-Signature')
  end

  def test_bank_transfer_other_banks_code_and_raw_body
    pay(bank_transfer_body.merge(bankTransfer: { bankCode: Lunixi::BANK_TRANSFER_OTHER_BANKS_CODE }))
    assert_equal({ 'bankCode' => '9999' }, JSON.parse(@transport.calls.last[:body])['bankTransfer'])
  end

  def test_bank_transfer_provider_code_is_rejected_by_builder_and_raw_body
    assert_raises(Lunixi::ConfigurationError) do
      Lunixi::DirectMethodPaymentRequest.new('10000', 'TRY', 'order_1').with_method_fields('BANK_TRANSFER', 'bank_a', bankCode: '0062')
    end
    assert_raises(Lunixi::ConfigurationError) do
      Lunixi::DirectMethodPaymentRequest.new('10000', 'TRY', 'order_1').with_method_fields('BANK_TRANSFER', nil, providerCode: 'bank_a', bankCode: '0062')
    end
    assert_rejected(bank_transfer_body.merge(bankTransfer: { providerCode: 'bank_a', bankCode: '0062' }))
    assert_empty @transport.calls
  end

  def test_raw_body_rules_stop_the_request_before_network
    assert_rejected(wallet_body.merge(mobileBilling: { gsmNumber: '+905321234567' }))
    assert_rejected(wallet_body.merge(installment: 3))
    assert_rejected(wallet_body.merge(card: { cardToken: 'token' }))
    assert_rejected(wallet_body.merge(unknownField: 'x'))
    assert_rejected(wallet_body.merge(price: '10000'))
    assert_rejected(wallet_body.except(:wallet))
    assert_rejected(wallet_body.except(:orderId))
    assert_rejected(wallet_body.merge(paymentMethod: 'GIFT_CARD'))
    assert_rejected(wallet_body.merge(paymentMethod: 'wallet'))
    assert_rejected(wallet_body.merge(preauth: 'true'))
    assert_rejected(wallet_body.merge(wallet: { providerCode: 'bad code' }))
    assert_rejected({ paymentMethod: 'CARD', amount: '10000', currency: 'TRY', orderId: 'order_1' })
    assert_rejected({ paymentMethod: 'CARD', amount: '10000', currency: 'TRY', orderId: 'order_1', card: { cardToken: 't' }, force3D: 'yes' })
    assert_empty @transport.calls
  end

  def test_idempotency_key_is_required
    [nil, '', 'short'].each do |key|
      assert_raises(Lunixi::ConfigurationError) { pay(wallet_body, key) }
    end
    assert_empty @transport.calls
    pay(wallet_body)
    assert_equal 'wallet_a', JSON.parse(@transport.calls.last[:body]).dig('wallet', 'providerCode')
  end

  def test_builder_rejects_card_fields_and_methods_without_a_block
    request = Lunixi::DirectMethodPaymentRequest.new('10000', 'TRY', 'order_1')
    assert_raises(Lunixi::ConfigurationError) { request.with_method_fields('CARD', nil, {}) }
    assert_raises(Lunixi::ConfigurationError) { request.with_method_fields('GIFT_CARD', nil, {}) }
    assert_raises(Lunixi::ConfigurationError) { request.to_h }
    request.with_method_fields('WALLET', 'wallet_a', {}).with_installment(3)
    assert_raises(Lunixi::ConfigurationError) { request.to_h }
    card = Lunixi::DirectMethodPaymentRequest.new('10000', 'try', 'order_1').with_card(cardToken: 'token', cardUserKey: 'user').with_force3d(true)
    assert_equal({ 'cardToken' => 'token', 'cardUserKey' => 'user' }, card.to_h['card'])
    assert_equal 'TRY', card.to_h['currency']
    assert_equal true, card.to_h['force3D']
  end

  def test_shopping_loan_requires_one_to_one_hundred_basket_items
    item = { id: 'item_1', name: 'Phone', itemType: 'PHYSICAL', price: '100', productCategory: 'MOBILE_PHONE' }
    body = { paymentMethod: 'SHOPPING_LOAN', amount: '10000', currency: 'TRY', orderId: 'order_1', shoppingLoan: { providerCode: 'loan_a' } }
    assert_rejected(body)
    assert_rejected(body.merge(basketItems: []))
    assert_rejected(body.merge(basketItems: Array.new(101) { item }))
    assert_empty @transport.calls
    pay(body.merge(basketItems: Array.new(100) { item }))
    assert_equal 100, JSON.parse(@transport.calls.last[:body])['basketItems'].size
  end

  def test_block_structure_limits
    many = (1..33).to_h { |index| ["field#{index}", 'x'] }
    group = Array.new(11) { { name: 'x' } }
    [many, { note: 'x' * 1025 }, { items: group }, { '__proto__' => 'x' }, { '1field' => 'x' }, { address: { line: { deep: 'x' } } },
     { value: nil }].each do |fields|
      assert_rejected(wallet_body.merge(wallet: { providerCode: 'wallet_a' }.merge(fields)))
      assert_raises(Lunixi::ConfigurationError) do
        Lunixi::DirectMethodPaymentRequest.new('10000', 'TRY', 'order_1').with_method_fields('WALLET', 'wallet_a', fields)
      end
    end
    assert_empty @transport.calls
    fields = { address: { provinceCode: '06', districtCode: '1234', line: 'Street 1' }, people: Array.new(10) { { name: 'x', age: 30 } },
               note: 'x' * 1024, consent: true }
    pay(Lunixi::DirectMethodPaymentRequest.new('10000', 'TRY', 'order_1').with_method_fields('WALLET', 'wallet_a', fields))
    assert_equal 10, JSON.parse(@transport.calls.last[:body]).dig('wallet', 'people').size
  end

  def test_promissory_note_plan_rules
    base = { paymentMethod: 'PROMISSORY_NOTE', amount: '10000', currency: 'TRY', orderId: 'order_1' }
    rows = [{ amount: '5000', dueDate: '2027-01-15' }, { amount: '5000', dueDate: '2027-02-15' }]
    [
      { providerCode: 'note_a', schedule: rows, noteCount: '2' },
      { providerCode: 'note_a' },
      { providerCode: 'note_a', schedule: [{ amount: '5000', dueDate: '2027-01-15' }, { amount: '4000', dueDate: '2027-02-15' }] },
      { providerCode: 'note_a', schedule: [{ amount: '10000', dueDate: '2027-02-30' }] },
      { providerCode: 'note_a', schedule: [{ amount: '5000', dueDate: '2027-02-15' }, { amount: '5000', dueDate: '2027-01-15' }] },
      { providerCode: 'note_a', schedule: [{ amount: '10000', dueDate: '2027-01-15', note: 'x' }] },
      { providerCode: 'note_a', noteCount: '25' },
      { providerCode: 'note_a', noteCount: '0' }
    ].each { |block| assert_rejected(base.merge(promissoryNote: block)) }
    long = Array.new(25) { { amount: '400', dueDate: '2027-01-15' } }
    assert_raises(Lunixi::ConfigurationError) { Lunixi::DirectMethodPaymentRequest.new('10000', 'TRY', 'order_1').with_promissory_note_schedule(long) }
    assert_empty @transport.calls

    pay(base.merge(promissoryNote: { providerCode: 'note_a', schedule: rows }))
    assert_equal 2, JSON.parse(@transport.calls.last[:body]).dig('promissoryNote', 'schedule').size
    request = Lunixi::DirectMethodPaymentRequest.new('10000', 'TRY', 'order_1')
                                                .with_method_fields('PROMISSORY_NOTE', 'note_a', debtorName: 'Buyer').with_promissory_note_count(3)
    pay(request)
    assert_equal({ 'providerCode' => 'note_a', 'debtorName' => 'Buyer', 'noteCount' => '3' }, JSON.parse(@transport.calls.last[:body])['promissoryNote'])
  end

  def test_confirm_and_resend_payment_action
    [{ token: 'x', otp: '123456' }, { checkoutSessionProof: 'x' }, { unknown: 1 }, { otp: '12a4' }, { otp: 123_456 }, { otp: '1' * 17 },
     { consentAccepted: 'yes' }, {}, { fields: { '__proto__' => 'x' } }].each do |input|
      assert_raises(Lunixi::ConfigurationError) { @sdk.payments.confirm_payment_action('pay_1', 'act_1', input) }
    end
    assert_raises(Lunixi::ConfigurationError) { @sdk.payments.confirm_payment_action('', 'act_1', otp: '1') }
    assert_raises(Lunixi::ConfigurationError) { @sdk.payments.resend_payment_action('pay_1', 'act/1') }
    assert_empty @transport.calls

    @sdk.payments.confirm_payment_action('pay_1', 'act_1', otp: '123456', consentAccepted: true)
    confirm = @transport.calls.last
    assert_equal '/api/v1/payments/pay_1/actions/act_1/confirm', confirm[:uri].path
    assert_equal '{"otp":"123456","consentAccepted":true}', confirm[:body]
    assert confirm[:headers].key?('X-Signature')
    @sdk.payments.resend_payment_action('pay_1', 'act_1')
    resend = @transport.calls.last
    assert_equal '/api/v1/payments/pay_1/actions/act_1/resend', resend[:uri].path
    assert_nil resend[:body]
    assert resend[:headers].key?('X-Signature')
  end
end
