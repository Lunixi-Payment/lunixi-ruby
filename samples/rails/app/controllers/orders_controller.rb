# frozen_string_literal: true

class OrdersController < ApplicationController
  before_action :load_order

  def show
    response.headers['Cache-Control'] = 'private, no-store'
    whole, fraction = @order.amount_minor.divmod(100)
    @display_amount = "#{whole}#{I18n.t('checkout.decimal')}#{fraction.to_s.rjust(2, '0')} TRY"
  end

  def checkout
    return redirect_to order_path(@order.public_id), status: :see_other if @order.status == 'paid'

    form_actions = CheckoutPolicy.form_action_sources
    CheckoutFlow.new(@order).start(callback_url, ENV.fetch('LUNIXI_CHECKOUT_MODE', 'embedded'))
    response.headers['Cache-Control'] = 'private, no-store'
    if @order.checkout_mode == 'hosted'
      redirect_to HostedCheckout.url(@order.payment_page_url), allow_other_host: true, status: :see_other
    else
      @checkout_config = Lunixi::Checkout.browser_config(@order.checkout_token)
      @checkout_nonce = SecureRandom.base64(18)
      response.headers['Content-Security-Policy'] = "default-src 'self'; script-src 'nonce-#{@checkout_nonce}' https://cdn.lunixi.com; " \
                                                    "frame-src https://*.lunixi.com; connect-src 'self' https://*.lunixi.com; " \
                                                    "form-action 'self' #{form_actions}; frame-ancestors 'none'; base-uri 'none'"
      render :payment
    end
  rescue Lunixi::Error, KeyError, JSON::ParserError
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
