# frozen_string_literal: true

require_relative '../test_helper'

class CheckoutTest < RailsFlowTest
  def test_requires_merchant_authentication
    get order_path(@order.public_id)
    assert_response :unauthorized
  end

  def test_requires_csrf_on_checkout
    post checkout_order_path(@order.public_id), headers: @auth
    assert_equal 422, response.status
    assert_empty @payments.intents
  end

  def test_uses_server_total_durable_key_and_encrypted_token
    checkout
    assert_redirected_to 'https://pay.lunixi.com/payment/checkout_TOKEN_synthetic_123'
    assert_equal 303, response.status
    assert_equal 10_050, @payments.intents.first.first[:amount]
    assert_equal @order.checkout_key, @payments.intents.first.last
    assert_equal 'https://pay.lunixi.com', @payments.intents.first.first.dig(:metadata, :allowedOrigin)
    assert_equal "https://merchant.example/orders/#{@order.public_id}/return", @payments.intents.first.first[:callbackUrl]
    @order.reload
    assert_equal 'pending', @order.status
    assert_equal 'intent_123', @order.intent_id
    refute_includes @order.ciphertext_for(:checkout_token), 'checkout_TOKEN_synthetic_123'
    checkout
    assert_equal 1, @payments.intents.size
  end

  def test_network_failure_leaves_order_pending_and_reuses_key
    @payments.failure = true
    checkout
    assert_response :service_unavailable
    assert_equal 'pending', @order.reload.status
    assert_nil @order.checkout_token
    @payments.failure = false
    checkout
    assert_response :see_other
    assert_equal [@order.checkout_key], @payments.intents.map(&:last).uniq
  end

  def test_conflicting_checkout_aliases_cannot_bind_another_payment
    @payments.checkout_response = { 'token' => 'checkout_TOKEN_synthetic_123', 'paymentId' => 'intent_123', 'intentId' => 'other-intent' }
    checkout
    assert_response :service_unavailable
    assert_nil @order.reload.intent_id
    assert_nil @order.checkout_token
  end

  def test_return_url_cannot_mark_paid
    get return_order_path(@order.public_id), params: { status: 'CAPTURED', paid: true }, headers: @auth
    assert_response :see_other
    assert_equal 'pending', @order.reload.status
    assert_empty @payments.reads
  end

  def test_cross_site_post_return_is_bounded_and_redirects_without_auth_or_side_effects
    post return_order_path(@order.public_id), params: { status: 'CAPTURED', public_id: 'another-order', redirect: 'https://attacker.example' }
    assert_response :see_other
    assert_equal return_order_path(@order.public_id), response.headers['Location']
    assert_equal 'pending', @order.reload.status
    assert_empty @payments.intents
    assert_empty @payments.reads
    follow_redirect!
    assert_response :unauthorized
    get return_order_path(@order.public_id), headers: @auth
    assert_response :see_other
    assert_redirected_to order_path(@order.public_id)
  end

  def test_oversized_stateless_return_does_not_read_an_order_or_gateway
    post return_order_path(@order.public_id), params: 'x' * 1_048_577, headers: { 'CONTENT_TYPE' => 'application/octet-stream' }
    assert_response :content_too_large
    assert_equal 'pending', @order.reload.status
    assert_empty @payments.intents
    assert_empty @payments.reads
  end

  def test_empty_stateless_post_return_also_resumes_through_owned_get
    post return_order_path(@order.public_id)
    assert_response :see_other
    assert_equal return_order_path(@order.public_id), response.headers['Location']
    assert_empty @payments.intents
  end

  def test_stored_checkout_token_cannot_supply_a_redirect_host
    @order.update!(checkout_token: '//attacker.example/collect')
    checkout
    assert_response :service_unavailable
    assert_nil response.headers['Location']
    assert_empty @payments.intents
  end

  def test_localizes_checkout_in_turkish
    get order_path(@order.public_id), params: { locale: 'tr' }, headers: @auth
    assert_response :ok
    assert_includes response.body, '100,50 TRY'
    assert_includes response.body, 'lang="tr"'
  end
end
