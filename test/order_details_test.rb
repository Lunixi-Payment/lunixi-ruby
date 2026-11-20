# frozen_string_literal: true

require_relative 'test_helper'

# Lunixi::OrderDetails names the missing order fields in the gateway's path format. Values are synthetic.
class OrderDetailsTest < Minitest::Test
  def complete
    { basketItems: [basket_item] }.merge(order_details)
  end

  def test_complete_order_details_have_no_missing_paths
    assert_empty Lunixi::OrderDetails.missing(complete)
    assert_empty Lunixi::OrderDetails.missing(JSON.parse(JSON.generate(complete)))
  end

  def test_missing_objects_and_fields_are_named_by_path
    assert_equal %w[buyer billingAddress basketItems], Lunixi::OrderDetails.missing({})
    assert_equal %w[buyer billingAddress basketItems], Lunixi::OrderDetails.missing(nil)
    body = complete.merge(buyer: order_details[:buyer].merge(email: ' ', ip: nil), billingAddress: 'Istanbul',
                          basketItems: [basket_item(category1: ''), 'item'])
    assert_equal %w[buyer.email buyer.ip billingAddress basketItems.0.category1 basketItems.1], Lunixi::OrderDetails.missing(body)
    assert_equal %w[basketItems], Lunixi::OrderDetails.missing(complete.merge(basketItems: []))
  end

  def test_shipping_address_is_required_for_a_physical_item
    assert_equal %w[shippingAddress], Lunixi::OrderDetails.missing(complete.except(:shippingAddress))
    virtual = complete.except(:shippingAddress).merge(basketItems: [basket_item(itemType: 'VIRTUAL')])
    assert_empty Lunixi::OrderDetails.missing(virtual)
    assert_equal %w[shippingAddress.contactName shippingAddress.address],
                 Lunixi::OrderDetails.missing(virtual.merge(shippingAddress: { city: 'Istanbul', country: 'Turkey', zipCode: '34000' }))
  end

  def test_checkout_intent_and_basket_options
    without_ip = complete.merge(buyer: order_details[:buyer].except(:ip))
    assert_equal %w[buyer.ip], Lunixi::OrderDetails.missing(without_ip)
    assert_empty Lunixi::OrderDetails.missing(without_ip, checkout_intent: true)
    assert_empty Lunixi::OrderDetails.missing(complete.except(:basketItems, :shippingAddress), basket: false)
    assert_equal %w[ip], Lunixi::CHECKOUT_INTENT_BUYER_OPTIONAL_FIELDS
  end

  def test_check_raises_a_configuration_error_naming_the_paths
    error = assert_raises(Lunixi::ConfigurationError) { Lunixi::OrderDetails.check!(complete.except(:billingAddress), 'A payment intent') }
    assert_equal 'A payment intent requires the order details: billingAddress.', error.message
    assert_equal complete, Lunixi::OrderDetails.check!(complete, 'A payment intent')
    assert_equal %w[payment.order.field_required payment.order.field_invalid], Lunixi::OrderFieldErrorCode::ALL
  end

  def test_create_intent_checks_before_sending
    transport = RecordingTransport.new { response }
    sdk = client(transport: transport)
    error = assert_raises(Lunixi::ConfigurationError) do
      sdk.payments.create_intent(payment_body.except(:buyer), idempotency_key: idempotency_key)
    end
    assert_equal 'A payment intent requires the order details: buyer.', error.message
    assert_empty transport.calls

    sdk.payments.create_intent(payment_body.merge(buyer: order_details[:buyer].except(:ip)), idempotency_key: idempotency_key)
    sent = sent_json(api_calls(transport).fetch(0))
    assert_equal 'Buyer', sent.dig('buyer', 'surname')
    refute sent['buyer'].key?('ip')
  end
end
