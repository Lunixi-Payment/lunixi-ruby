# frozen_string_literal: true

require_relative 'test_helper'

class PaymentsTest < Minitest::Test
  def setup
    @transport = RecordingTransport.new { response }
    @sdk = client(transport: @transport)
  end

  def test_rejects_unsafe_money_and_removed_fields_before_network
    [0, -1, 100.5, '100', 9_007_199_254_740_992].each do |amount|
      assert_raises(Lunixi::ConfigurationError) { @sdk.payments.create_intent(payment_body.merge(amount: amount), idempotency_key: idempotency_key) }
    end
    %i[price paidPrice].each do |field|
      assert_raises(Lunixi::ConfigurationError) { @sdk.payments.create_intent(payment_body.merge(field => nil), idempotency_key: idempotency_key) }
    end
    assert_raises(Lunixi::ConfigurationError) { @sdk.payments.create_intent(payment_body.merge(preauth: 'false'), idempotency_key: idempotency_key) }
    assert_empty @transport.calls
  end

  def test_rejects_mismatched_basket_or_split_total_and_insecure_callback
    assert_raises(Lunixi::ConfigurationError) { @sdk.payments.create_intent(payment_body.merge(amount: '50'), idempotency_key: idempotency_key) }
    assert_raises(Lunixi::ConfigurationError) { @sdk.payments.create_intent(payment_body.merge(callbackUrl: 'http://merchant.example'), idempotency_key: idempotency_key) }
    assert_raises(Lunixi::ConfigurationError) { @sdk.payments.split({ totalAmount: '100', currency: 'TRY', ownerRef: 'owner_1', legs: [{ amount: '80' }] }, idempotency_key: idempotency_key) }
    assert_empty @transport.calls
  end

  def test_requires_a_durable_valid_idempotency_key
    ['', 'short', 'contains spaces in the key', "header\r\ninjection", 'x' * 129].each do |key|
      assert_raises(Lunixi::ConfigurationError) { @sdk.payments.refund('pay_1', idempotency_key: key) }
    end
    assert_empty @transport.calls
  end

  def test_explicit_nil_never_becomes_a_full_capture_or_refund
    %i[capture refund].each do |operation|
      assert_raises(Lunixi::ConfigurationError) { @sdk.payments.public_send(operation, 'pay_1', amount: nil, idempotency_key: idempotency_key) }
      assert_raises(Lunixi::ConfigurationError) { @sdk.request('POST', "/api/v1/payments/pay_1/#{operation}", body: { amount: nil }, idempotency_key: idempotency_key) }
    end
    assert_empty @transport.calls
    @sdk.payments.capture('pay_1', idempotency_key: idempotency_key)
    @sdk.payments.refund('pay_1', idempotency_key: idempotency_key)
    @transport.calls.drop(1).each { |request| refute JSON.parse(request[:body]).key?('amount') }
  end

  def test_false_optional_amount_never_becomes_a_full_capture_or_refund
    %i[capture refund].each do |method|
      assert_raises(Lunixi::ConfigurationError) do
        @sdk.payments.public_send(method, 'pay_1', amount: false, idempotency_key: idempotency_key)
      end
    end
    assert_empty @transport.calls
  end

  def test_capture_refund_void_methods_and_split_refund_match_gateway_routes
    @sdk.payments.capture('pay_1', amount: '50', idempotency_key: idempotency_key)
    @sdk.payments.refund('pay_1', amount: '40', reason: 'Customer request', idempotency_key: idempotency_key)
    @sdk.payments.void('pay_1', idempotency_key: idempotency_key)
    @sdk.payments.methods(payment_method: 'MEAL_CARD')
    @sdk.payments.refund_split('split_1', amount: '50', idempotency_key: idempotency_key)
    expected_paths = %w[
      /api/v1/payments/pay_1/capture /api/v1/payments/pay_1/refund /api/v1/payments/pay_1/void
      /api/v1/payments/methods /api/v1/payments/split/split_1/refund
    ]
    assert_equal(expected_paths, @transport.calls.drop(1).map { |request| request[:uri].path })
  end

  def test_fraud_rejects_tenant_override_and_uses_documented_endpoint
    assert_raises(Lunixi::ConfigurationError) { @sdk.fraud.evaluate(tenantId: 'other_tenant') }
    @sdk.fraud.evaluate(transactionRef: 'transaction_1', integrationMode: 'PAYMENT_GATEWAY', payment: { amount: '100', currency: 'TRY' })
    assert_equal '/api/v1/fraud/decisions/evaluate', @transport.calls.last[:uri].path
    refute @transport.calls.last[:headers].key?('X-Signature')
  end
end
