# frozen_string_literal: true

module Lunixi
  # Checks of the BIN, installment and stored-card bodies. Card numbers, BINs and security codes never
  # appear in an error message.
  module CardRules
    BIN_OR_PAN_PATTERN = /\A[0-9]{6,19}\z/
    INSTALLMENT_MAX = 36
    TEXT_MAX_BYTES = 255

    module_function

    # A 6 or 8 digit BIN or a card number prefix, digits only.
    def bin_or_pan!(value)
      raise ConfigurationError, 'binOrPan must be 6 to 19 digits (a BIN or a card number prefix)' unless value.is_a?(String) && value.match?(BIN_OR_PAN_PATTERN)

      value
    end

    def installment!(value)
      raise ConfigurationError, "installment must be an integer from 1 to #{INSTALLMENT_MAX}" unless value.is_a?(Integer) && value.between?(1, INSTALLMENT_MAX)

      value
    end

    def currency!(value)
      raise ConfigurationError, 'Currency must be a three-letter uppercase code' unless value.is_a?(String) && value.match?(/\A[A-Z]{3}\z/)

      value
    end

    def text!(value, field)
      unless value.is_a?(String) && !value.strip.empty? && value.bytesize <= TEXT_MAX_BYTES && !value.match?(/[\x00-\x1f\x7f]/)
        raise ConfigurationError, "#{field} must be a nonempty string of at most #{TEXT_MAX_BYTES} bytes"
      end

      value
    end

    # Body of POST /api/v1/bin/installments: amount (or intentId), currency and the optional binOrPan,
    # installment, cardBrand and enabledInstallments (sent in ascending order).
    def installment_options_body!(body)
      data = plain!(body, 'Installment options request')
      raise ConfigurationError, 'Installment options need amount or intentId' if data['amount'].nil? && data['intentId'].nil?

      Money.minor(data['amount']) unless data['amount'].nil?
      text!(data['intentId'], 'intentId') unless data['intentId'].nil?
      currency!(data['currency']) unless data['currency'].nil?
      bin_or_pan!(data['binOrPan']) unless data['binOrPan'].nil?
      installment!(data['installment']) unless data['installment'].nil?
      data['enabledInstallments'] = EnabledInstallments.check!(data['enabledInstallments']) if data.key?('enabledInstallments')
      data
    end

    # Body of POST /api/v1/payments/cards: card, cardUserKey, an HTTPS callbackUrl and an optional currency.
    def store_card_body!(body)
      data = plain!(body, 'Store card request')
      raise ConfigurationError, 'Store card request requires the card object' unless data['card'].is_a?(Hash) && !data['card'].empty?

      text!(data['cardUserKey'], 'cardUserKey')
      callback_url!(data['callbackUrl'])
      currency!(data['currency']) unless data['currency'].nil?
      data
    end

    def callback_url!(url)
      uri = URI.parse(url)
      raise ConfigurationError, 'callbackUrl must use HTTPS' unless uri.is_a?(URI::HTTPS) && uri.host && !uri.userinfo && !uri.fragment && url.bytesize <= 2048

      url
    rescue URI::InvalidURIError, TypeError
      raise ConfigurationError, 'Invalid callbackUrl', cause: nil
    end

    def plain!(body, name)
      body = body.to_h if body.is_a?(InstallmentOptionsRequest) || body.is_a?(StoreCardRequest)
      raise ConfigurationError, "#{name} must be an object" unless body.is_a?(Hash)

      JSON.parse(JsonBody.dump(body))
    end
  end

  # Body of payments.installment_options: the installment table for an amount and, with a BIN, the
  # binding quote token of installment > 1. Its inspect output never shows the card number.
  class InstallmentOptionsRequest
    def initialize(amount, currency)
      @payload = { 'amount' => Money.minor(amount), 'currency' => CardRules.currency!(currency.to_s.upcase) }
    end

    # A 6 or 8 digit BIN or a card number prefix.
    def with_bin_or_pan(value)
      @payload['binOrPan'] = CardRules.bin_or_pan!(value)
      self
    end

    # With an intent the intent's own enabledInstallments list applies first.
    def with_intent_id(value)
      @payload['intentId'] = CardRules.text!(value, 'intentId')
      self
    end

    def with_installment(value)
      @payload['installment'] = CardRules.installment!(value)
      self
    end

    def with_card_brand(value)
      @payload['cardBrand'] = CardRules.text!(value, 'cardBrand')
      self
    end

    # Limits the table to these counts (e.g. [1, 2, 3]); the rules of the intent's enabledInstallments.
    def with_enabled_installments(counts)
      @payload['enabledInstallments'] = EnabledInstallments.check!(counts)
      self
    end

    def to_h
      @payload.dup
    end

    def inspect
      "#<#{self.class.name} amount=#{@payload['amount']} currency=#{@payload['currency']}>"
    end
  end

  # Body of payments.store_card (verify and store a card for cardUserKey). Its inspect output never
  # shows the card.
  class StoreCardRequest
    def initialize(card, card_user_key, callback_url)
      raise ConfigurationError, 'card must be an object' unless card.is_a?(Hash) && !card.empty?

      @payload = { 'card' => card, 'cardUserKey' => CardRules.text!(card_user_key, 'cardUserKey'),
                   'callbackUrl' => CardRules.callback_url!(callback_url) }
    end

    def with_currency(value)
      @payload['currency'] = CardRules.currency!(value.to_s.upcase)
      self
    end

    def to_h
      @payload.dup
    end

    def inspect
      "#<#{self.class.name} card=[REDACTED]>"
    end
  end
end
