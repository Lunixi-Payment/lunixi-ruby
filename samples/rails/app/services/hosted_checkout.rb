# frozen_string_literal: true

# Validate the backend URL again on reuse; never construct one from a browser token.
class HostedCheckout
  def self.url(value)
    Lunixi::Checkout.payment_page_url(value)
  end
end
