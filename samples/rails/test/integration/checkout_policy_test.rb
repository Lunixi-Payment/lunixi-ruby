# frozen_string_literal: true

require_relative '../test_helper'

class CheckoutPolicyTest < RailsFlowTest
  def test_rendered_checkout_csp_preserves_nonce_and_allows_only_gateway_posts
    checkout
    assert_response :ok
    policy = response.headers.fetch('Content-Security-Policy')
    directives = policy.split(';').to_h { |part| part.strip.split(' ', 2) }
    assert_equal "'self' https://api-gateway.lunixi.com", directives.fetch('form-action')
    nonce = response.parsed_body.at_css('script[nonce]')['nonce']
    assert_includes directives.fetch('script-src'), "'nonce-#{nonce}'"
    assert_equal "'none'", directives.fetch('frame-ancestors')
    assert_equal 'no-referrer', response.headers['Referrer-Policy']
    refute_includes policy, 'form-action https:'
  end

  def test_rendered_checkout_csp_uses_explicit_operator_origins
    ENV['LUNIXI_BASE_URL'] = 'https://gateway.example:8443'
    ENV['LUNIXI_FORM_ACTION_ORIGINS'] = 'https://provider.example,https://gateway.example:8443'
    checkout
    assert_response :ok
    directive = response.headers.fetch('Content-Security-Policy').split(';').find { |part| part.strip.start_with?('form-action ') }
    assert_equal "form-action 'self' https://gateway.example:8443 https://provider.example", directive.strip
  end

  def test_invalid_operator_form_origins_fail_before_creating_an_intent
    ['https:', 'https://*.example.com', 'https://user@provider.example', 'http://provider.example',
     'https://provider.example/', 'https://provider.example/post', 'https://provider.example?x=1',
     'https://provider.example#x', "https://provider.example\r\nform-action https:",
     'https://provider.example;form-action https:', 'https://provider.example\\evil',
     'https://provider.example:0', 'https://provider.example:65536', 'https://provider.example,'].each do |origin|
      ENV['LUNIXI_FORM_ACTION_ORIGINS'] = origin
      checkout
      assert_response :service_unavailable
      refute_includes response.body, origin
      assert_nil response.headers['Location']
      assert_empty @payments.intents
      assert_nil @order.reload.checkout_request
    end
  end
end
