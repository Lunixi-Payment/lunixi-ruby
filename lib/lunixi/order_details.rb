# frozen_string_literal: true

module Lunixi
  # Order details every payment endpoint requires: the buyer, the billing address and at least one
  # basket item; a basket with a PHYSICAL item also requires the shipping address. Payment providers do
  # not start a payment without them.
  #
  # The gateway refuses a missing field with payment.order.field_required and an invalid one with
  # payment.order.field_invalid; details.field is the dotted path of the first failing field. The SDK
  # checks the same rule before sending and names the same paths. The same values as the Node, PHP and
  # Python SDKs.

  # Order objects required on every payment endpoint.
  ORDER_DETAILS_REQUIRED_FIELDS = %w[buyer billingAddress basketItems].freeze

  # buyer fields that must be nonempty strings. identityNumber: Turkish ID or passport number; email:
  # ASCII; ip: the buyer's browser IP (IPv4 or IPv6).
  BUYER_REQUIRED_FIELDS = %w[name surname identityNumber email gsmNumber city country zipCode ip].freeze

  # buyer fields a checkout intent may leave out (payments.create_intent, payments.create_marketplace_intent,
  # marketplace.create_checkout_intent): the Lunixi form takes the IP from the buyer's browser. A given
  # ip is still sent and wins.
  CHECKOUT_INTENT_BUYER_OPTIONAL_FIELDS = %w[ip].freeze

  # Fields of billingAddress and shippingAddress that must be nonempty strings.
  ADDRESS_REQUIRED_FIELDS = %w[contactName address city country zipCode].freeze

  # Fields of each basketItems[] entry the gateway requires.
  BASKET_ITEM_REQUIRED_FIELDS = %w[id name category1 itemType price].freeze

  # Error codes of a missing or invalid order field.
  module OrderFieldErrorCode
    FIELD_REQUIRED = 'payment.order.field_required'
    FIELD_INVALID = 'payment.order.field_invalid'

    ALL = [FIELD_REQUIRED, FIELD_INVALID].freeze
  end

  # details.reason of an order field error.
  module OrderFieldReason
    REQUIRED = 'required'
    REQUIRED_WHEN_PHYSICAL = 'required_when_physical'
    INVALID_TYPE = 'invalid_type'
    INVALID_FORMAT = 'invalid_format'
    TOO_LONG = 'too_long'
    TOO_FEW_ITEMS = 'too_few_items'

    ALL = [REQUIRED, REQUIRED_WHEN_PHYSICAL, INVALID_TYPE, INVALID_FORMAT, TOO_LONG, TOO_FEW_ITEMS].freeze
  end

  # The order details check of the payment endpoints.
  module OrderDetails
    PHYSICAL_ITEM_TYPE = 'PHYSICAL'

    module_function

    # Paths of the missing order fields of a payment body (String or Symbol keys), in the gateway's
    # format: buyer, buyer.email, billingAddress.city, basketItems.0.category1, shippingAddress. An empty
    # Array means the order details are complete. basket: false checks the buyer and the billing address
    # only (card storage, wallet card top-up); checkout_intent: true does not require
    # CHECKOUT_INTENT_BUYER_OPTIONAL_FIELDS.
    def missing(body, basket: true, checkout_intent: false)
      data = body.is_a?(Hash) ? JSON.parse(JsonBody.dump(body)) : {}
      buyer_fields = checkout_intent ? BUYER_REQUIRED_FIELDS - CHECKOUT_INTENT_BUYER_OPTIONAL_FIELDS : BUYER_REQUIRED_FIELDS
      paths = object_paths(data['buyer'], buyer_fields, 'buyer') +
              object_paths(data['billingAddress'], ADDRESS_REQUIRED_FIELDS, 'billingAddress')
      return paths unless basket

      items = data['basketItems']
      return paths << 'basketItems' unless items.is_a?(Array) && !items.empty?

      paths.concat(basket_paths(items))
      shipping = data['shippingAddress']
      if shipping.nil?
        paths << 'shippingAddress' if items.any? { |item| item.is_a?(Hash) && item['itemType'] == PHYSICAL_ITEM_TYPE }
      else
        paths.concat(object_paths(shipping, ADDRESS_REQUIRED_FIELDS, 'shippingAddress'))
      end
      paths
    end

    # Raises ConfigurationError naming the missing order fields (see missing); label names the request
    # ("A payment intent").
    def check!(body, label, basket: true, checkout_intent: false)
      paths = missing(body, basket: basket, checkout_intent: checkout_intent)
      raise ConfigurationError, "#{label} requires the order details: #{paths.join(', ')}." unless paths.empty?

      body
    end

    def object_paths(value, fields, path)
      return [path] unless value.is_a?(Hash)

      fields.reject { |field| filled?(value[field]) }.map { |field| "#{path}.#{field}" }
    end

    def basket_paths(items)
      items.each_with_index.flat_map do |item, index|
        next ["basketItems.#{index}"] unless item.is_a?(Hash)

        BASKET_ITEM_REQUIRED_FIELDS.select { |field| blank?(item[field]) }.map { |field| "basketItems.#{index}.#{field}" }
      end
    end

    def filled?(value)
      value.is_a?(String) && !value.strip.empty?
    end

    def blank?(value)
      value.nil? || (value.is_a?(String) && value.strip.empty?)
    end

    private_class_method :object_paths, :basket_paths, :filled?, :blank?
  end
end
