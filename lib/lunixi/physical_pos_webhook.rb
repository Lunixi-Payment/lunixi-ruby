# frozen_string_literal: true

require 'json'

module Lunixi
  # One verified physical POS webhook (frozen).
  #
  # id: the event id (the same transition always carries the same id). type: physical_pos.payment.*,
  # physical_pos.fiscal_document.* or physical_pos.settlement.*. category: payment, fiscal_document,
  # settlement or other (a type a later release may add). environment: LIVE or TEST when present.
  # created_at: when the transition happened (ISO 8601), when present. history_seq: the payment's /
  # document's historySeq, or nil (end-of-day events carry none). original: a reversal's original
  # payment { 'paymentId', 'origin' } (origin API or DEVICE_DIRECT), nil on a root payment. cashier:
  # { 'cashierId', 'cashierCode' } for a payment started from a device cashier session, nil otherwise
  # (the payload then has no cashier key). device_sale?: true for physical_pos.payment.device_sale, a
  # sale made directly on the device (data carries origin and deviceOccurredAt). data: the payload.
  # raw: the whole envelope.
  PhysicalPosWebhookEvent = Struct.new(:id, :type, :category, :environment, :created_at, :history_seq, :original, :cashier,
                                       :device_sale, :data, :raw, keyword_init: true) do
    def device_sale?
      device_sale == true
    end
  end

  # Verifies and reads a physical POS webhook. There is no way in without the signature: pass the exact
  # raw request body, the request headers and your webhook secret (or a configured WebhookVerifier).
  # The signature, event id and timestamp are checked by WebhookVerifier; any mismatch raises
  # WebhookError before the body is read.
  #
  #   event = Lunixi::PhysicalPosWebhook.parse(request.raw_post, request.headers.to_h, secret)
  #   handle_approval(event.data) if event.type == Lunixi::PhysicalPosEvents::PAYMENT_APPROVED
  #
  # The event body is the envelope's data; an envelope that carries it under payloadJson (an object or
  # that object as a JSON string) is read the same way. The type comes from the signed body only.
  # Amounts in the payload are minor-unit strings ("4500"), matching the HTTP API, and are checked
  # after the signature.
  #
  # Delivery order is not guaranteed and an event can arrive more than once: deduplicate by id and
  # ignore an event whose history_seq is not greater than the last one you applied for the same
  # data['paymentId']. End-of-day events (category settlement) carry no historySeq; deduplicate them by
  # id. When in doubt, read the payment with get_payment.
  module PhysicalPosWebhook
    PREFIX = 'physical_pos.'
    CATEGORY_PAYMENT = 'payment'
    CATEGORY_FISCAL_DOCUMENT = 'fiscal_document'
    CATEGORY_SETTLEMENT = 'settlement'
    CATEGORY_OTHER = 'other'

    module_function

    # secret_or_verifier: your webhook secret, [current, *previous] secrets during rotation, or a
    # WebhookVerifier. tolerance (seconds) is used only when secrets are given.
    def parse(raw_body, headers, secret_or_verifier, tolerance: 300)
      verified = verifier_for(secret_or_verifier, tolerance).verify(raw_body, headers)
      envelope = verified.raw
      type = text(envelope['type']) || text(envelope['eventType']) || verified.type
      raise WebhookError, "Not a physical POS webhook event (type: #{type || 'missing'})" unless type.is_a?(String) && type.start_with?(PREFIX)

      data = payload(envelope)
      validate_money(data)
      seq = data['historySeq']
      PhysicalPosWebhookEvent.new(
        id: text(envelope['id']) || text(envelope['eventId']) || verified.id, type: type, category: category(type),
        environment: text(envelope['environment']),
        created_at: text(envelope['createdAt']) || text(envelope['occurredAt']) || text(envelope['timestamp']),
        history_seq: seq.is_a?(Integer) ? seq : nil, original: original(data), cashier: cashier(data),
        device_sale: type == PhysicalPosEvents::PAYMENT_DEVICE_SALE, data: data, raw: envelope
      ).freeze
    end

    # The original payment of a reversal event: { 'paymentId', 'origin' } when data['original'] carries
    # both as non-empty strings (other keys are dropped); otherwise nil (a root payment).
    def original(data)
      pair(data, 'original', 'paymentId', 'origin')
    end

    # The cashier of a payment event: { 'cashierId', 'cashierCode' } when data['cashier'] carries both
    # as non-empty strings (other keys are dropped); otherwise nil (no cashier session).
    def cashier(data)
      pair(data, 'cashier', 'cashierId', 'cashierCode')
    end

    # payment, fiscal_document, settlement or other.
    def category(type)
      return CATEGORY_PAYMENT if type.start_with?("#{PREFIX}payment.")
      return CATEGORY_FISCAL_DOCUMENT if type.start_with?("#{PREFIX}fiscal_document.")
      return CATEGORY_SETTLEMENT if type.start_with?("#{PREFIX}settlement.")

      CATEGORY_OTHER
    end

    def pair(data, name, first, second)
      value = data.is_a?(Hash) ? data[name] : nil
      return nil unless value.is_a?(Hash)

      left = text(value[first])
      right = text(value[second])
      left && right ? { first => left, second => right }.freeze : nil
    end

    def verifier_for(secret_or_verifier, tolerance)
      return secret_or_verifier if secret_or_verifier.is_a?(WebhookVerifier)

      unless secret_or_verifier.is_a?(String) || (secret_or_verifier.is_a?(Array) && !secret_or_verifier.empty?)
        raise ConfigurationError, 'Pass your webhook secret (or [current, *previous] secrets) or a WebhookVerifier'
      end

      secrets = Array(secret_or_verifier)
      WebhookVerifier.new(secret: secrets.first, previous_secrets: secrets.drop(1), tolerance: tolerance)
    end

    def payload(envelope)
      data = envelope['data']
      return data if data.is_a?(Hash) && !data.empty?

      carried = envelope['payloadJson']
      carried = parse_payload_json(carried) if carried.is_a?(String)
      return deep_freeze(carried) if carried.is_a?(Hash) && !carried.empty?

      raise WebhookError, 'The physical POS webhook carries no event data (data / payloadJson)'
    end

    def parse_payload_json(text)
      JSON.parse(text, max_nesting: 64)
    rescue JSON::ParserError
      raise WebhookError, 'The physical POS webhook payloadJson is not valid JSON', cause: nil
    end

    def validate_money(data)
      PhysicalPosMoney.validate(data)
    rescue ConfigurationError
      raise WebhookError, 'The physical POS webhook carries a non-canonical amount (minor-unit string expected)', cause: nil
    end

    def text(value)
      value.is_a?(String) && !value.empty? ? value : nil
    end

    def deep_freeze(value)
      case value
      when Hash then value.each_value { |entry| deep_freeze(entry) }
      when Array then value.each { |entry| deep_freeze(entry) }
      end
      value.freeze
    end
  end
end
