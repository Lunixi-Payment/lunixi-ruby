# frozen_string_literal: true

class OrdersController < ApplicationController
  before_action :load_order

  def show
    response.headers['Cache-Control'] = 'private, no-store'
    whole, fraction = @order.amount_minor.divmod(100)
    @display_amount = "#{whole}#{I18n.t('checkout.decimal')}#{fraction.to_s.rjust(2, '0')} TRY"
  end

  def checkout
    @order.with_lock do
      return redirect_to order_path(@order.public_id), status: :see_other if @order.status == 'paid'

      unless @order.checkout_token.present?
        payload = LunixiConnection.client.payments.create_intent(
          { amount: @order.amount_minor, currency: @order.currency, orderId: @order.public_id,
            callbackUrl: callback_url, metadata: { allowedOrigin: 'https://pay.lunixi.com' } }, idempotency_key: @order.checkout_key
        ).fetch('data')
        token = payload.fetch('token')
        identifiers = payload.values_at('paymentId', 'intentId').compact
        intent_id = identifiers.first
        raise Lunixi::Error, 'Conflicting checkout identifiers' unless identifiers.uniq.one?
        unless token.is_a?(String) && token.match?(/\A[A-Za-z0-9_.~-]{16,4096}\z/) && intent_id.is_a?(String) && intent_id.match?(/\A[a-zA-Z0-9_-]{1,256}\z/)
          raise Lunixi::Error, 'Unexpected checkout response'
        end

        @order.update!(checkout_token: token, intent_id: intent_id)
      end
      redirect_to HostedCheckout.url(@order.checkout_token), allow_other_host: true, status: :see_other
    end
  rescue Lunixi::Error, KeyError
    render plain: I18n.t('checkout.unavailable'), status: :service_unavailable
  end

  def return_from_payment
    # A return URL or browser query never changes payment state.
    redirect_to order_path(@order.public_id), status: :see_other
  end

  private

  def load_order
    @order = Order.find_by!(public_id: params[:public_id])
  end

  def callback_url
    origin = ENV.fetch('PUBLIC_ORIGIN')
    uri = URI.parse(origin)
    unless uri.is_a?(URI::HTTPS) && uri.host && !uri.userinfo && !uri.query && !uri.fragment && ['', '/'].include?(uri.path)
      raise Lunixi::ConfigurationError, 'PUBLIC_ORIGIN must be an HTTPS origin'
    end

    "#{origin.delete_suffix('/')}/orders/#{@order.public_id}/return"
  end
end
