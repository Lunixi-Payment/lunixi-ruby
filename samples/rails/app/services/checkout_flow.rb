# frozen_string_literal: true

# Freeze the attempt before network I/O; native row locks serialize response binding.
class CheckoutFlow
  def initialize(order)
    @order = order
  end

  def start(callback, requested_mode)
    raise Lunixi::Error, 'Invalid checkout presentation' unless %w[embedded hosted].include?(requested_mode)

    reserve(callback, requested_mode)
    @order.with_lock do
      raise Lunixi::Error, 'Checkout requires reconciliation' unless @order.status == 'pending'

      raise Lunixi::Error, 'Stored checkout presentation is invalid' unless %w[embedded hosted].include?(@order.checkout_mode)

      reserved_payload if @order.checkout_request.present?

      if @order.checkout_token.present?
        Lunixi::Checkout.browser_config(@order.checkout_token)
      else
        create_from_reserved_request
      end
    end
    @order
  end

  private

  def reserve(callback, requested_mode)
    @order.with_lock do
      raise Lunixi::Error, 'Checkout requires reconciliation' unless @order.status == 'pending'
      return if @order.checkout_request.present? || @order.checkout_token.present?
      raise Lunixi::Error, 'Legacy checkout requires reconciliation' if @order.checkout_legacy || @order.intent_id.present?

      metadata = requested_mode == 'hosted' ? { allowedOrigin: 'https://pay.lunixi.com' } : {}
      payload = { amount: @order.amount_minor, currency: @order.currency, orderId: @order.public_id,
                  callbackUrl: callback, metadata: metadata }
      @order.update!(checkout_mode: requested_mode, checkout_request: JSON.generate(payload), checkout_started_at: Time.current)
    end
  end

  def reserved_payload
    payload = JSON.parse(@order.checkout_request)
    unless payload.values_at('amount', 'currency', 'orderId') == [@order.amount_minor, @order.currency, @order.public_id]
      raise Lunixi::Error, 'Persisted order changed; reconcile checkout'
    end

    expected_metadata = @order.checkout_mode == 'hosted' ? { 'allowedOrigin' => 'https://pay.lunixi.com' } : {}
    raise Lunixi::Error, 'Stored checkout mode changed; reconcile checkout' unless payload['metadata'] == expected_metadata

    payload
  end

  def create_from_reserved_request
    age = @order.checkout_started_at && (Time.current - @order.checkout_started_at)
    raise Lunixi::Error, 'Retry window expired; reconcile checkout' unless age&.between?(-300, (23 * 3600) - 1)

    payload = reserved_payload
    response = LunixiConnection.client.payments.create_intent(payload, idempotency_key: @order.checkout_key).fetch('data')
    token = response.fetch('token')
    Lunixi::Checkout.browser_config(token)
    identifiers = %w[paymentId intentId].select { |key| response.key?(key) }.map { |key| response.fetch(key) }
    intent_id = identifiers.first
    unless identifiers.uniq.length == 1 && intent_id.is_a?(String) && intent_id.match?(/\A[a-zA-Z0-9_-]{1,256}\z/)
      raise Lunixi::Error, 'Conflicting or invalid checkout identity'
    end

    page_url = response['paymentPageUrl']
    page_url = Lunixi::Checkout.payment_page_url(page_url) unless page_url.nil?
    @order.update!(checkout_token: token, intent_id: intent_id, payment_page_url: page_url)
  end
end
