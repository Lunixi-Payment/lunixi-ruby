# frozen_string_literal: true

class WebhookProcessor
  class InconsistentPayment < Lunixi::Error; end

  def initialize(client: LunixiConnection.client, store: RailsReplayStore.new,
                 verifier: Lunixi::WebhookVerifier.new(secret: Rails.configuration.x.lunixi_webhook_secret))
    @client = client
    @store = store
    @verifier = verifier
  end

  def call(raw_body, headers)
    @verifier.process(raw_body, headers, store: @store) do |event|
      # Other subscribed events are recorded but never interpreted as payment success.
      next unless event.type == 'payment.captured'

      order = locate_order(event)
      next if order.status == 'paid'

      validate_payment!(order, @client.payments.get(order.intent_id))

      order.update!(status: 'paid')
    end
  end

  private

  def locate_order(event)
    identifiers = event.data.values_at('intentId', 'paymentIntentId', 'paymentId').compact
    intent_id = identifiers.first
    order_id = event.data['orderId']
    unless identifiers.uniq.one? && intent_id.is_a?(String) && order_id.is_a?(String)
      raise InconsistentPayment, 'Payment correlation fields are missing or inconsistent'
    end

    Order.lock.find_by!(public_id: order_id, intent_id: intent_id)
  end

  def validate_payment!(order, envelope)
    payment = envelope.fetch('data')
    valid = payment.is_a?(Hash) && payment['status'] == 'CAPTURED' &&
            payment['id'] == order.intent_id && payment['merchantId'] == Rails.configuration.x.lunixi_merchant_id &&
            payment['orderId'] == order.public_id && payment['currency'] == order.currency &&
            minor(payment['amount']) == order.amount_minor &&
            !payment['split'] && minor(envelope.dig('details', 'capturedAmount')) == order.amount_minor &&
            minor(envelope.dig('details', 'refundedAmount')).zero?
    raise InconsistentPayment, 'Payment requires reconciliation' unless valid
  end

  def minor(value)
    Lunixi::Money.minor(value, positive: false).to_i
  rescue Lunixi::ConfigurationError
    raise InconsistentPayment, 'Authenticated settlement amount is missing or invalid'
  end
end
