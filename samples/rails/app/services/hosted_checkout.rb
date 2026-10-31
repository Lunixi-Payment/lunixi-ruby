# frozen_string_literal: true

# Build an absolute URL from a fixed origin; neither the browser nor a gateway
# response can supply a scheme or host. Validate stored tokens again on reuse.
class HostedCheckout
  def self.url(token)
    raise Lunixi::Error, 'Checkout token is invalid' unless token.is_a?(String) && token.match?(/\A[A-Za-z0-9_.~-]{16,4096}\z/)

    URI::HTTPS.build(host: 'pay.lunixi.com', path: "/payment/#{token}").to_s
  end
end
