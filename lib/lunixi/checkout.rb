# frozen_string_literal: true

module Lunixi
  # Browser-safe configuration and strict backend-supplied optional hosted URLs.
  module Checkout
    def self.payment_page_url(value)
      unless value.is_a?(String) && value.match?(%r{\Ahttps://pay\.lunixi\.com/payment/[A-Za-z0-9_.~-]{16,4096}\z})
        raise Error, 'A valid backend paymentPageUrl is required'
      end

      value.dup.freeze
    end

    def self.browser_config(token)
      raise Error, 'Checkout token is invalid' unless token.is_a?(String) && token.match?(/\A[A-Za-z0-9_.~-]{16,4096}\z/)

      { type: 'payment', target: 'lunixi-checkout-form', options: { token: token } }
    end
  end
end
