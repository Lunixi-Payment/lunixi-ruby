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
    assert_response :ok
    assert_nil response.headers['Location']
    assert_includes response.body, 'https://cdn.lunixi.com/lunixi-checkout.min.js'
    assert_includes response.body, "Lunixi.checkout.create(config).mount('#lunixi-checkout-form')"
    assert_includes response.headers['Content-Security-Policy'], 'script-src'
    assert_includes response.headers['Cache-Control'], 'no-store'
    assert_equal 10_050, @payments.intents.first.first['amount']
    assert_equal @order.checkout_key, @payments.intents.first.last
    assert_equal({}, @payments.intents.first.first.fetch('metadata'))
    assert_equal 'embedded', @order.reload.checkout_mode
    assert_equal "https://merchant.example/orders/#{@order.public_id}/return", @payments.intents.first.first['callbackUrl']
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
    assert_response :ok
    assert_equal [@order.checkout_key], @payments.intents.map(&:last).uniq
  end

  def test_conflicting_checkout_aliases_cannot_bind_another_payment
    @payments.checkout_response = { 'token' => 'checkout_TOKEN_synthetic_123', 'paymentId' => 'intent_123', 'intentId' => 'other-intent' }
    checkout
    assert_response :service_unavailable
    assert_nil @order.reload.intent_id
    assert_nil @order.checkout_token
  end

  def test_optional_hosted_uses_exact_encrypted_backend_url_and_keeps_frozen_mode
    ENV['LUNIXI_CHECKOUT_MODE'] = 'hosted'
    checkout
    assert_redirected_to 'https://pay.lunixi.com/payment/server-issued-page-0123456789'
    assert_equal 'https://pay.lunixi.com', @payments.intents.first.first.dig('metadata', 'allowedOrigin')
    @order.reload
    refute_includes @order.ciphertext_for(:payment_page_url), 'server-issued-page'
    refute_includes @order.ciphertext_for(:checkout_request), 'merchant.example'
    ENV['LUNIXI_CHECKOUT_MODE'] = 'embedded'
    checkout
    assert_redirected_to 'https://pay.lunixi.com/payment/server-issued-page-0123456789'
    assert_equal 'hosted', @order.reload.checkout_mode
    assert_equal 1, @payments.intents.size
  end

  def test_missing_hosted_url_is_held_without_rebuilding_or_new_network_call
    ENV['LUNIXI_CHECKOUT_MODE'] = 'hosted'
    @payments.checkout_response = { 'token' => 'checkout_TOKEN_synthetic_123', 'paymentId' => 'intent_123' }
    checkout
    assert_response :service_unavailable
    assert_nil response.headers['Location']
    assert_equal 'intent_123', @order.reload.intent_id
    checkout
    assert_response :service_unavailable
    assert_equal 1, @payments.intents.size
  end

  def test_unsafe_hosted_url_is_not_a_redirect_and_preserves_original_reservation
    ENV['LUNIXI_CHECKOUT_MODE'] = 'hosted'
    @payments.checkout_response = { 'token' => 'checkout_TOKEN_synthetic_123', 'paymentId' => 'intent_123',
                                    'paymentPageUrl' => 'https://pay.lunixi.com.evil.invalid/payment/server-issued-page-0123456789' }
    key = @order.checkout_key
    checkout
    assert_response :service_unavailable
    assert_nil response.headers['Location']
    assert_equal key, @order.reload.checkout_key
    assert @order.checkout_request.present?
    assert_nil @order.intent_id
  end

  def test_uncertain_attempt_reuses_original_mode_body_and_observes_age_fence
    ENV['LUNIXI_CHECKOUT_MODE'] = 'hosted'
    @payments.failure = true
    checkout
    assert_response :service_unavailable
    body = @order.reload.checkout_request
    key = @order.checkout_key
    ENV['LUNIXI_CHECKOUT_MODE'] = 'embedded'
    @payments.failure = false
    checkout
    assert_redirected_to 'https://pay.lunixi.com/payment/server-issued-page-0123456789'
    assert_equal body, @order.reload.checkout_request
    assert_equal key, @order.checkout_key
    @order.update!(checkout_token: nil, intent_id: nil, checkout_started_at: 24.hours.ago)
    calls = @payments.intents.size
    checkout
    assert_response :service_unavailable
    assert_equal calls, @payments.intents.size
  end

  def test_stored_backend_url_cannot_supply_a_redirect_host
    @order.update!(checkout_mode: 'hosted', checkout_token: 'checkout_TOKEN_synthetic_123', checkout_legacy: true,
                   payment_page_url: 'https://evil.invalid/payment/server-issued-page-0123456789')
    checkout
    assert_response :service_unavailable
    assert_nil response.headers['Location']
    assert_empty @payments.intents
  end

  def test_malicious_browser_token_cannot_escape_the_embedded_page
    @payments.checkout_response = { 'token' => '</script><script>evil</script>', 'paymentId' => 'intent_123' }
    checkout
    assert_response :service_unavailable
    refute_includes response.body, '<script>evil'
    assert_nil @order.reload.checkout_token
  end

  def test_legacy_unknown_request_requires_reconciliation
    @order.update!(checkout_legacy: true, checkout_mode: 'hosted')
    checkout
    assert_response :service_unavailable
    assert_empty @payments.intents
  end

  def test_changed_native_order_does_not_reuse_a_frozen_checkout
    checkout
    @order.update!(amount_minor: 20_000)
    checkout
    assert_response :service_unavailable
    assert_equal 1, @payments.intents.size
  end

  def test_present_null_alias_cannot_bind_a_different_or_missing_identity
    @payments.checkout_response = { 'token' => 'checkout_TOKEN_synthetic_123', 'paymentId' => 'intent_123', 'intentId' => nil }
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
