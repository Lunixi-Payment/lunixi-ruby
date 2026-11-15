# frozen_string_literal: true

module Lunixi
  # Request rules of the payment-method endpoints, checked before anything is sent. The fields inside
  # a method block are the provider's declaration (inputFields) and are validated by the gateway; these
  # rules stop a body the gateway would reject for its shape alone.
  module MethodFields
    METHOD_CODE_PATTERN = /\A[A-Z][A-Z0-9_]{0,31}\z/
    PROVIDER_CODE_PATTERN = /\A[A-Za-z0-9_-]{1,64}\z/
    FIELD_KEY_PATTERN = /\A[A-Za-z][A-Za-z0-9]{0,63}\z/
    RESERVED_FIELD_KEYS = %w[__proto__ constructor prototype].freeze
    MAX_KEYS = 32
    MAX_NESTED_KEYS = 16
    MAX_GROUP_ITEMS = 10
    MAX_VALUE_LENGTH = 1024
    OTP_PATTERN = /\A[0-9]{1,16}\z/

    module_function

    # Canonical method code; QR becomes QR_CODE.
    def normalize_payment_method(value)
      unless value.is_a?(String) && value.match?(METHOD_CODE_PATTERN)
        raise ConfigurationError, 'paymentMethod must be a payment method code such as MOBILE_BILLING'
      end

      PaymentMethod::ALIASES.fetch(value, value)
    end

    # Name of the method's block in the body: the camelCase method code (BANK_TRANSFER -> bankTransfer).
    def block_name_of(payment_method)
      normalize_payment_method(payment_method).downcase.gsub(/_([a-z0-9])/) { Regexp.last_match(1).upcase }
    end

    def provider_code!(value)
      unless value.is_a?(String) && value.match?(PROVIDER_CODE_PATTERN)
        raise ConfigurationError, 'providerCode must be a provider code from payments.list_payment_methods (letters, digits, _ and -)'
      end

      value
    end

    # A method block or confirm fields: at most 32 fields; a value is a string (at most 1024 characters),
    # a finite number, a boolean, an object of such values (ADDRESS, at most 16 fields) or a list of at
    # most 10 objects (GROUP). providerCode is never part of the fields.
    def method_fields!(value, path)
      raise ConfigurationError, "#{path} must be an object of field values" unless value.is_a?(Hash)
      raise ConfigurationError, "#{path} can carry at most #{MAX_KEYS} fields" if value.size > MAX_KEYS

      value.each do |key, field|
        raise ConfigurationError, "#{path} must not carry providerCode; pass it as its own argument" if key == 'providerCode'

        field_key!(key, path)
        field_value!(field, "#{path}.#{key}", allow_list: true)
      end
      value
    end

    # A SHOPPING_LOAN payment needs the basket (1 to 100 items): the bank sets the loan term from it.
    def shopping_loan_basket!(payment_method, basket_items)
      return unless payment_method == PaymentMethod::SHOPPING_LOAN
      unless basket_items.is_a?(Array) && !basket_items.empty?
        raise ConfigurationError, 'paymentMethod SHOPPING_LOAN requires basketItems: the bank sets the loan term from the basket'
      end
      return if basket_items.size <= SHOPPING_LOAN_MAX_BASKET_ITEMS

      raise ConfigurationError, "paymentMethod SHOPPING_LOAN takes at most #{SHOPPING_LOAN_MAX_BASKET_ITEMS} basket items"
    end

    # Body of POST /payments/{paymentId}/actions/{actionId}/confirm: otp, consentAccepted and fields only.
    def confirm_body!(input)
      raise ConfigurationError, 'Confirm input must be an object: { otp:, consentAccepted:, fields: }' unless input.is_a?(Hash)

      data = JSON.parse(JsonBody.dump(input))
      unknown = data.keys - PAYMENT_ACTION_CONFIRM_FIELDS
      unless unknown.empty?
        raise ConfigurationError, "Unknown confirm field(s): #{unknown.join(', ')}; a merchant server sends only #{PAYMENT_ACTION_CONFIRM_FIELDS.join(', ')}"
      end

      body = {}
      unless data['otp'].nil?
        raise ConfigurationError, 'otp must be the code the buyer entered, as digits' unless data['otp'].is_a?(String) && data['otp'].match?(OTP_PATTERN)

        body['otp'] = data['otp']
      end
      unless data['consentAccepted'].nil?
        raise ConfigurationError, 'consentAccepted must be a boolean' unless [true, false].include?(data['consentAccepted'])

        body['consentAccepted'] = data['consentAccepted']
      end
      body['fields'] = method_fields!(data['fields'], 'fields') unless data['fields'].nil?
      raise ConfigurationError, 'confirm_payment_action needs otp, consentAccepted or fields' if body.empty?

      body
    end

    def field_key!(key, path)
      return if key.is_a?(String) && key.match?(FIELD_KEY_PATTERN) && !RESERVED_FIELD_KEYS.include?(key)

      raise ConfigurationError, "#{path} has an invalid field name: names start with a letter and contain only letters and digits"
    end

    def scalar?(value)
      (value.is_a?(String) && value.length <= MAX_VALUE_LENGTH) ||
        (value.is_a?(Integer) || (value.is_a?(Float) && value.finite?)) ||
        [true, false].include?(value)
    end

    def field_value!(value, path, allow_list:)
      return if scalar?(value)
      return nested_object!(value, path) if value.is_a?(Hash)
      return group!(value, path) if allow_list && value.is_a?(Array)

      raise ConfigurationError, "#{path} must be a string (at most #{MAX_VALUE_LENGTH} characters), a number, a boolean, an object or a list of objects"
    end

    def nested_object!(value, path)
      raise ConfigurationError, "#{path} can carry at most #{MAX_NESTED_KEYS} fields" if value.size > MAX_NESTED_KEYS

      value.each do |key, field|
        field_key!(key, path)
        raise ConfigurationError, "#{path}.#{key} must be a string, a number or a boolean" unless scalar?(field)
      end
    end

    def group!(items, path)
      raise ConfigurationError, "#{path} can carry at most #{MAX_GROUP_ITEMS} items" if items.size > MAX_GROUP_ITEMS

      items.each_with_index do |item, index|
        item_path = "#{path}[#{index}]"
        raise ConfigurationError, "#{item_path} must be an object" unless item.is_a?(Hash)
        raise ConfigurationError, "#{item_path} can carry at most #{MAX_KEYS} fields" if item.size > MAX_KEYS

        item.each do |key, field|
          field_key!(key, item_path)
          field_value!(field, "#{item_path}.#{key}", allow_list: false)
        end
      end
    end

    private_class_method :field_key!, :scalar?, :field_value!, :nested_object!, :group!
  end
end
