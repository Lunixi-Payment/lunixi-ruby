# frozen_string_literal: true

require_relative 'test_helper'

class HostedCheckoutTest < ActiveSupport::TestCase
  def test_only_a_fixed_https_origin_is_possible
    %W[https://attacker.example //attacker.example ../path token\r\nLocation: https://evil.example a?query=b a#fragment].each do |token|
      assert_raises(Lunixi::Error) { HostedCheckout.url(token) }
    end
    assert_equal 'https://pay.lunixi.com/payment/checkout_TOKEN_synthetic', HostedCheckout.url('checkout_TOKEN_synthetic')
  end
end
