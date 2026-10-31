# frozen_string_literal: true

require_relative 'test_helper'

class CheckoutHelpersTest < Minitest::Test
  def test_backend_page_url_is_returned_exactly_and_never_derived_from_token
    page = 'https://pay.lunixi.com/payment/server-issued-page-0123456789'
    assert_equal page, Lunixi::Checkout.payment_page_url(page)
    assert_raises(Lunixi::Error) { Lunixi::Checkout.payment_page_url('browser_token_0123456789') }
    assert_raises(Lunixi::Error) { Lunixi::Checkout.payment_page_url("#{page}?redirect=evil") }
  end

  def test_embedded_configuration_has_only_the_official_object_mount_contract
    token = 'browser_token_0123456789'
    assert_equal({ type: 'payment', target: 'lunixi-checkout-form', options: { token: token } }, Lunixi::Checkout.browser_config(token))
    assert_raises(Lunixi::Error) { Lunixi::Checkout.browser_config('</script><script>evil') }
  end
end
