# frozen_string_literal: true

require_relative 'test_helper'

class HostedCheckoutTest < ActiveSupport::TestCase
  def test_only_a_fixed_https_origin_is_possible
    [nil, '', 'checkout_TOKEN_synthetic', 'https://attacker.example', '//attacker.example',
     'https://pay.lunixi.com.evil.invalid/payment/server-issued-page-0123456789',
     'https://pay.lunixi.com:443/payment/server-issued-page-0123456789',
     "https://pay.lunixi.com/payment/server-issued-page-0123456789\n",
     'https://pay.lunixi.com/payment/server-issued-page-0123456789?x=1'].each do |url|
      assert_raises(Lunixi::Error) { HostedCheckout.url(url) }
    end
    assert_equal 'https://pay.lunixi.com/payment/server-issued-page-0123456789',
                 HostedCheckout.url('https://pay.lunixi.com/payment/server-issued-page-0123456789')
  end
end
