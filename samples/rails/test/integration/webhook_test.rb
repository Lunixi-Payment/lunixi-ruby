# frozen_string_literal: true

require_relative '../test_helper'

class PaymentWebhookTest < RailsFlowTest
  setup do
    @order.update!(intent_id: 'intent_123')
    @payments.payment = captured_payment
  end

  def test_external_webhook_requires_signature_without_basic_auth_or_csrf
    post '/webhooks/lunixi', params: '{}', headers: { 'CONTENT_TYPE' => 'application/json' }
    assert_response :bad_request
    assert_equal 0, LunixiReceipt.count
    assert_equal 'pending', @order.reload.status
  end

  def test_commits_receipt_and_paid_state_once
    event = signed_event
    2.times do
      deliver(event)
      assert_response :ok
    end
    assert_equal 'paid', @order.reload.status
    assert_equal 1, LunixiReceipt.count
    assert_equal ['intent_123'], @payments.reads
  end

  def test_event_type_may_come_from_the_signed_body_without_optional_header
    raw, headers = signed_event
    headers.delete('x-lunixi-event-type')
    deliver([raw, headers])
    assert_response :ok
    assert_equal 'paid', @order.reload.status
  end

  def test_rolls_back_receipt_and_payment_on_wrong_amount
    @payments.payment = captured_payment(amount: "1")
    event = signed_event
    deliver(event)
    assert_response :service_unavailable
    assert_equal 0, LunixiReceipt.count
    assert_equal 'pending', @order.reload.status
    @payments.payment = captured_payment
    deliver(event)
    assert_response :ok
    assert_equal 'paid', @order.reload.status
  end

  def test_retries_same_event_after_failed_gateway_read
    event = signed_event
    @payments.failure = true
    deliver(event)
    assert_response :service_unavailable
    assert_equal 0, LunixiReceipt.count
    @payments.failure = false
    deliver(event)
    assert_response :ok
    assert_equal 'paid', @order.reload.status
  end

  def test_reused_event_id_with_changed_payload_is_rejected
    deliver
    assert_response :ok
    deliver(signed_event(data: { orderId: @order.public_id, intentId: 'different_intent' }))
    assert_response :bad_request
    assert_equal 1, LunixiReceipt.count
  end

  def test_signed_unrelated_or_failed_events_never_fulfil_order
    deliver(signed_event(type: 'payment.failed'))
    assert_response :ok
    assert_equal 'pending', @order.reload.status
    assert_empty @payments.reads
  end

  def test_signed_captured_with_wrong_order_is_not_accepted
    deliver(signed_event(data: { orderId: 'someone-elses-order', intentId: 'intent_123' }))
    assert_response :service_unavailable
    assert_equal 0, LunixiReceipt.count
    assert_equal 'pending', @order.reload.status
  end

  def test_unknown_status_or_wrong_currency_stays_pending
    [{ 'status' => 'AUTHORIZED' }, { 'currency' => 'USD' }, { 'amount' => '10050' }].each do |change|
      @payments.payment = captured_payment.merge(change)
      deliver
      assert_response :service_unavailable
      assert_equal 0, LunixiReceipt.count
      assert_equal 'pending', @order.reload.status
    end
  end

  def test_authenticated_id_and_merchant_must_match_the_persisted_payment
    [{ 'id' => 'another-payment' }, { 'merchantId' => 'another-merchant' }, { 'split' => { 'role' => 'LEG' } }].each do |change|
      @payments.payment = captured_payment.merge(change)
      deliver
      assert_response :service_unavailable
      assert_equal 0, LunixiReceipt.count
      assert_equal 'pending', @order.reload.status
    end
  end

  def test_partial_or_missing_settlement_never_fulfils_order
    [{ 'capturedAmount' => '9900', 'refundedAmount' => '0' }, { 'capturedAmount' => '10050', 'refundedAmount' => '1' }, {}].each do |settlement|
      @payments.settlement = settlement
      deliver
      assert_response :service_unavailable
      assert_equal 0, LunixiReceipt.count
      assert_equal 'pending', @order.reload.status
    end
  end
end
