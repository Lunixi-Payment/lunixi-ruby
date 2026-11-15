# frozen_string_literal: true

module Lunixi
  # One verified bank-connect, bank-transfer or insurance webhook (frozen). id: the event id (the same on
  # every redelivery; deduplicate on it). type: one of the product's event names. environment: TEST or
  # LIVE when present. created_at: the envelope's createdAt. data: the documented data fields of the
  # event (a field the event did not carry is nil; no other key is kept). raw: the whole envelope.
  ProductWebhookEvent = Struct.new(:id, :type, :environment, :created_at, :data, :raw, keyword_init: true) do
    def [](name)
      data[name.to_s]
    end
  end

  # Reads product webhooks through the signature check, never around it. Not a public API; use
  # BankConnectWebhook, BankTransferWebhook or InsuranceWebhook.
  module ProductWebhook
    module_function

    # fields: { event type => data field list }. Amounts in data must be canonical minor-unit strings.
    def parse(raw_body, headers, secret_or_verifier, fields, label, tolerance)
      verified = PhysicalPosWebhook.verifier_for(secret_or_verifier, tolerance).verify(raw_body, headers)
      read(verified, fields, label)
    end

    # An event already verified by WebhookVerifier#verify (or #process).
    def read(verified, fields, label)
      raise ConfigurationError, 'Pass a Lunixi::VerifiedEvent from WebhookVerifier#verify' unless verified.is_a?(VerifiedEvent)

      list = fields[verified.type]
      raise WebhookError, "Not a #{label} webhook event (type: #{verified.type})" if list.nil?

      data = list.to_h { |name| [name, verified.data[name]] }
      begin
        Money.validate_fields(data, response: true)
      rescue ConfigurationError
        raise WebhookError, "The #{label} webhook carries a non-canonical amount (minor-unit string expected)", cause: nil
      end
      envelope = verified.raw
      ProductWebhookEvent.new(id: verified.id, type: verified.type, environment: text(envelope['environment']),
                              created_at: text(envelope['createdAt']), data: data.freeze, raw: envelope).freeze
    end

    def text(value)
      value.is_a?(String) && !value.empty? ? value : nil
    end
  end

  # bank_account.transaction.received (BankConnectEvents): data holds
  # BANK_ACCOUNT_TRANSACTION_RECEIVED_FIELDS.
  #
  #   event = Lunixi::BankConnectWebhook.parse(request.raw_post, request.headers.to_h, secret)
  #   book(event['transactionId'], event['amountMinor']) unless seen?(event.id)
  module BankConnectWebhook
    FIELDS = BankConnectEvents::ALL.to_h { |type| [type, BANK_ACCOUNT_TRANSACTION_RECEIVED_FIELDS] }.freeze

    module_function

    # secret_or_verifier: your webhook secret, [current, *previous] secrets during rotation, or a
    # WebhookVerifier. Raises WebhookError for a bad signature or another event type.
    def parse(raw_body, headers, secret_or_verifier, tolerance: 300)
      ProductWebhook.parse(raw_body, headers, secret_or_verifier, FIELDS, 'bank account', tolerance)
    end

    def from_event(verified_event)
      ProductWebhook.read(verified_event, FIELDS, 'bank account')
    end
  end

  # bank_transfer.* (BankTransferEvents, Bank Connect transfers): data holds BANK_TRANSFER_WEBHOOK_FIELDS.
  # The event says what happened; read the current state with bank_connect.transfers.get.
  module BankTransferWebhook
    FIELDS = BankTransferEvents::ALL.to_h { |type| [type, BANK_TRANSFER_WEBHOOK_FIELDS] }.freeze

    module_function

    def parse(raw_body, headers, secret_or_verifier, tolerance: 300)
      ProductWebhook.parse(raw_body, headers, secret_or_verifier, FIELDS, 'bank transfer', tolerance)
    end

    def from_event(verified_event)
      ProductWebhook.read(verified_event, FIELDS, 'bank transfer')
    end
  end

  # insurance.* (InsuranceEvents). An order event's data holds INSURANCE_WEBHOOK_FIELDS; the lead event
  # (insurance.lead.submitted) holds INSURANCE_LEAD_WEBHOOK_FIELDS and is not an order. Decide on the
  # order from the webhook; get_order shows its state.
  module InsuranceWebhook
    FIELDS = InsuranceEvents::ORDER_EVENTS.to_h { |type| [type, INSURANCE_WEBHOOK_FIELDS] }
                                          .merge(InsuranceEvents::LEAD_SUBMITTED => INSURANCE_LEAD_WEBHOOK_FIELDS).freeze

    module_function

    def parse(raw_body, headers, secret_or_verifier, tolerance: 300)
      ProductWebhook.parse(raw_body, headers, secret_or_verifier, FIELDS, 'insurance', tolerance)
    end

    def from_event(verified_event)
      ProductWebhook.read(verified_event, FIELDS, 'insurance')
    end

    def lead_event?(event)
      InsuranceEvents::LEAD_EVENTS.include?(event.type)
    end
  end
end
