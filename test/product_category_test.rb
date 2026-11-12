# frozen_string_literal: true

require_relative 'test_helper'

class ProductCategoryTest < Minitest::Test
  EXPECTED = %w[
    MOBILE_PHONE TABLET COMPUTER TV_AUDIO WHITE_GOODS SMALL_APPLIANCE CAMERA GAME_CONSOLE WEARABLE
    ELECTRONICS_ACCESSORY ELECTRONICS_OTHER GOLD JEWELRY WATCH APPAREL SHOES_BAGS COSMETICS FURNITURE
    HOME_LIVING GROCERY BOOKS_MEDIA TOYS SPORTS_OUTDOOR PET_SUPPLIES AUTO_PARTS MUSICAL_INSTRUMENT
    MICROMOBILITY VEHICLE TRANSPORT_TICKET EVENT_TICKET ACCOMMODATION TRAVEL_PACKAGE HEALTH_SERVICE EDUCATION
    SHIPPING_SERVICE DIGITAL_GOODS GIFT_CARD SUBSCRIPTION SERVICE_OTHER OTHER
  ].freeze

  def test_all_lists_the_forty_codes_in_dictionary_order
    assert_equal EXPECTED, Lunixi::ProductCategory::ALL
    assert_equal 40, Lunixi::ProductCategory::ALL.uniq.size
    assert_predicate Lunixi::ProductCategory::ALL, :frozen?
    EXPECTED.each { |code| assert_equal code, Lunixi::ProductCategory.const_get(code) }
  end

  def test_create_intent_sends_product_category_unchanged
    transport = RecordingTransport.new { response }
    item = { id: 'item_1', name: 'Test item', itemType: 'PHYSICAL', price: '10050',
             productCategory: Lunixi::ProductCategory::MOBILE_PHONE }
    client(transport: transport).payments.create_intent(payment_body.merge(basketItems: [item]), idempotency_key: idempotency_key)
    sent = JSON.parse(transport.calls.last[:body])
    assert_equal 'MOBILE_PHONE', sent.fetch('basketItems').first.fetch('productCategory')
  end
end
