# frozen_string_literal: true

module Lunixi
  # Explicit payment routes. The advanced Client#request method covers other
  # documented endpoints without pretending to validate their entire DTO schema.
  class Payments
    BASE = '/api/v1/payments'
    BIN_BASE = '/api/v1/bin'
    PDF_ACCEPT = 'application/pdf, application/json'
    OMITTED_AMOUNT = Object.new.freeze
    private_constant :OMITTED_AMOUNT
    attr_reader :client

    def initialize(client)
      @client = client
    end

    # Create hosted/embedded checkout using integer minor units and a durable attempt key.
    #
    # Optional +enabledInstallments+ (an Array of Integer) lists the installment counts the hosted
    # form may offer for this payment, e.g. <tt>[1, 2, 3]</tt>; <tt>[1]</tt> allows a single payment
    # only. The form shows only the counts also allowed by the panel settings, the card and the
    # platform maximum. Leave it out for no restriction. The list must hold distinct integers 1–36
    # that include 1; any other list, an empty one included, raises ConfigurationError before sending,
    # and the list is sent in ascending order.
    #
    # The order details are required (OrderDetails): +buyer+ (+ip+ may be left out here: the Lunixi
    # form takes it from the buyer's browser), +billingAddress+ and +basketItems+ (at least one; the
    # prices add up to +amount+); +shippingAddress+ when an item is PHYSICAL. A missing field raises
    # ConfigurationError naming its path before sending.
    #
    # @param body [Hash] gateway body: +amount+ (canonical minor-unit string), +currency+, +orderId+,
    #   the order details and optional fields such as +callbackUrl+ and +enabledInstallments+
    # @param idempotency_key [String] the persisted key of this checkout attempt
    # @return [Hash] Unmodified gateway response envelope; creation is not settlement.
    def create_intent(body, idempotency_key:)
      body = payment_body!(body)
      raise ConfigurationError, 'Intent installments are selected in the checkout form' if body.key?('installment')

      OrderDetails.check!(body, 'A payment intent', checkout_intent: true)
      client.request('POST', "#{BASE}/intents", body: body, idempotency_key: Client.idempotency_key!(idempotency_key))
    end

    # Create a marketplace intent (POST /payments/marketplace/intents, signed): the intent body plus
    # sellers [{ subDealerId, amountMinor, scenario }] and multiSellerPolicy. Each amountMinor is a
    # canonical minor-unit string and the sellers must add up to amount; any other total raises
    # ConfigurationError before sending. The order details follow the rule of create_intent.
    def create_marketplace_intent(body, idempotency_key:)
      data = payment_body!(body)
      sellers!(data['sellers'], data['amount'])
      OrderDetails.check!(data, 'A marketplace payment intent', checkout_intent: true)
      client.request('POST', "#{BASE}/marketplace/intents", body: data, idempotency_key: Client.idempotency_key!(idempotency_key))
    end

    # Card and bank details of a BIN (6 or 8 digits) or a card number prefix (POST /bin/info). The
    # value is never written to an error message.
    def bin_info(bin_or_pan)
      client.request('POST', "#{BIN_BASE}/info", body: { 'binOrPan' => CardRules.bin_or_pan!(bin_or_pan) }, signed: false)
    end

    # The installment table (POST /bin/installments) for an InstallmentOptionsRequest or a raw Hash; with
    # a BIN and installment > 1 the answer carries the binding quoteToken. enabledInstallments follows
    # the rule of create_intent and is sent in ascending order.
    def installment_options(body_or_request)
      client.request('POST', "#{BIN_BASE}/installments", body: CardRules.installment_options_body!(body_or_request), signed: false)
    end

    # Brand, family and bank reference lists (GET /bin/card-taxonomy).
    def card_taxonomy
      client.request('GET', "#{BIN_BASE}/card-taxonomy", signed: false)
    end

    # Verify and store a card for a cardUserKey (POST /payments/cards, signed). Build the body with
    # StoreCardRequest or pass a raw Hash; the idempotency key is required. The buyer (the card holder)
    # and the billing address are required (OrderDetails, no basket).
    def store_card(body_or_request, idempotency_key: nil)
      body = CardRules.store_card_body!(body_or_request)
      client.request('POST', "#{BASE}/cards", body: body, idempotency_key: Client.idempotency_key!(idempotency_key))
    end

    # Stored cards of a cardUserKey (GET /payments/cards?cardUserKey=); masked card data only.
    def list_stored_cards(card_user_key)
      client.request('GET', "#{BASE}/cards", query: { cardUserKey: CardRules.text!(card_user_key, 'cardUserKey') }, signed: false)
    end

    def get_stored_card(stored_card_token)
      client.request('GET', "#{BASE}/cards/#{identifier!(stored_card_token)}", signed: false)
    end

    # Deactivate a stored card (DELETE /payments/cards/{token}, signed); the idempotency key is required.
    def deactivate_stored_card(stored_card_token, idempotency_key: nil)
      client.request('DELETE', "#{BASE}/cards/#{identifier!(stored_card_token)}", idempotency_key: Client.idempotency_key!(idempotency_key))
    end

    # Payments rescued by provider failover retries (GET /payments/analytics/failover-recovery).
    # Filters such as from, to or range are sent as the query.
    def failover_recovery_analytics(**filters)
      client.request('GET', "#{BASE}/analytics/failover-recovery", query: filters, signed: false)
    end

    # Performance of one provider credential (GET /payments/analytics/provider-credentials/{id}).
    def provider_credential_analytics(credential_id, **filters)
      client.request('GET', "#{BASE}/analytics/provider-credentials/#{identifier!(credential_id)}", query: filters, signed: false)
    end

    # @return [Hash] Authenticated payment status envelope for reconciliation.
    def get(payment_id)
      client.request('GET', "#{BASE}/#{identifier!(payment_id)}", signed: false)
    end

    # @param filters [Hash] Documented gateway payment list query fields.
    def list(**filters)
      client.request('GET', BASE, query: filters, signed: false)
    end

    # Return merchant-enabled methods; the shared Lunixi form owns the final available list. Each method
    # lists its blockName, providerSelection, providerSelectionMode and providers with the inputFields
    # of the method block. payment_method narrows the list to one method code (QR is sent as QR_CODE).
    def methods(payment_method: nil)
      query = payment_method.nil? ? {} : { paymentMethod: MethodFields.normalize_payment_method(payment_method) }
      client.request('GET', "#{BASE}/methods", query: query)
    end
    alias list_payment_methods methods

    # Start a payment with any method from the merchant server (POST /payments/direct/payment). Build
    # the body with DirectMethodPaymentRequest or pass a raw Hash; both are checked before sending,
    # the order details (OrderDetails) included.
    # When the buyer must act, data.action says how (PaymentActionType); a BANK_TRANSFER payment
    # answers with a DISPLAY action read by BankTransferInstruction.from_response.
    def direct_method_payment(body_or_request, idempotency_key: nil)
      body = body_or_request.is_a?(DirectMethodPaymentRequest) ? body_or_request.to_h : DirectMethodPaymentRequest.payload!(body_or_request)
      OrderDetails.check!(body, 'A direct method payment')
      client.request('POST', "#{BASE}/direct/payment", body: body, idempotency_key: Client.idempotency_key!(idempotency_key))
    end

    # Complete the open action of a payment with { otp:, consentAccepted:, fields: } (at least one).
    def confirm_payment_action(payment_id, action_id, input)
      client.request('POST', action_path(payment_id, action_id, 'confirm'), body: MethodFields.confirm_body!(input))
    end

    # Send a new one-time code; the previous action is closed, confirm with the new data.action.id.
    def resend_payment_action(payment_id, action_id)
      client.request('POST', action_path(payment_id, action_id, 'resend'))
    end

    # The notes of a promissory-note payment with their status (PromissoryNoteStatus).
    def get_promissory_notes(payment_id)
      client.request('GET', promissory_notes_path(payment_id))
    end

    # Cancel notes; without serial_numbers every open note is cancelled. cancelResults[] gives the
    # result per note (PromissoryNoteCancelResult, PromissoryNoteCancelErrorCode).
    def cancel_promissory_notes(payment_id, serial_numbers: nil, idempotency_key: nil)
      body = serial_numbers.nil? ? nil : { 'serialNumbers' => PromissoryNotePlan.serial_numbers!(serial_numbers) }
      key = idempotency_key.nil? ? nil : Client.idempotency_key!(idempotency_key)
      client.request('POST', "#{promissory_notes_path(payment_id)}/cancel", body: body, idempotency_key: key)
    end

    # The printable notes as PDF bytes (a frozen binary String), one note per page. Not stored by the
    # gateway: download it when you need it. locale is one of PromissoryNoteDocumentLocale::ALL.
    def download_promissory_note_document(payment_id, locale: nil)
      query = locale.nil? ? {} : { locale: PromissoryNotePlan.document_locale!(locale) }
      client.request('GET', "#{promissory_notes_path(payment_id)}/document", query: query, binary: true, accept: PDF_ACCEPT)
    end

    # Late, short and excess transfers of BANK_TRANSFER payments; data.items[] of the envelope.
    def list_bank_transfer_exceptions(environment: nil, status: nil, limit: nil)
      query = BankTransferExceptions.query!(environment: environment, status: status, limit: limit)
      client.request('GET', "#{BASE}/bank-transfer/exceptions", query: query)
    end

    # Accept a LATE or UNDERPAID exception; data is the exception or nil.
    def accept_bank_transfer_exception(exception_id)
      client.request('POST', "#{BASE}/bank-transfer/exceptions/#{BankTransferExceptions.exception_id!(exception_id)}/accept")
    end

    # Report that you refunded the money of an exception to the sender from your own bank.
    def mark_bank_transfer_exception_refunded(exception_id)
      client.request('POST', "#{BASE}/bank-transfer/exceptions/#{BankTransferExceptions.exception_id!(exception_id)}/refunded")
    end

    # Omit amount to capture the remaining authorization; explicit nil is invalid.
    def capture(payment_id, idempotency_key:, amount: OMITTED_AMOUNT)
      body = { 'paymentIntentId' => identifier!(payment_id) }
      body['amount'] = minor!(amount) unless amount.equal?(OMITTED_AMOUNT)
      client.request('POST', "#{BASE}/#{payment_id}/capture", body: body, idempotency_key: Client.idempotency_key!(idempotency_key))
    end

    # Refund captured funds; persist a separate key for each refund operation.
    def refund(payment_id, idempotency_key:, amount: OMITTED_AMOUNT, reason: nil)
      body = { 'paymentIntentId' => identifier!(payment_id) }
      body['amount'] = minor!(amount) unless amount.equal?(OMITTED_AMOUNT)
      body['reason'] = reason!(reason) unless reason.nil?
      client.request('POST', "#{BASE}/#{payment_id}/refund", body: body, idempotency_key: Client.idempotency_key!(idempotency_key))
    end

    # Void an authorization without inventing a settlement success result.
    def void(payment_id, idempotency_key:)
      client.request('POST', "#{BASE}/#{identifier!(payment_id)}/void", idempotency_key: Client.idempotency_key!(idempotency_key))
    end

    # Start a 1–5 leg split payment; running statuses are returned, never marked paid. The body
    # (SPLIT_PAYMENT_FIELDS) carries the order details: buyer, billingAddress, basketItems and
    # shippingAddress for a PHYSICAL item; a missing field raises ConfigurationError before sending.
    def split(body, idempotency_key:)
      data = normalize!(body)
      minor!(data['totalAmount'])
      currency!(data['currency'])
      text!(data['ownerRef'])
      legs = data['legs']
      raise ConfigurationError, 'Split payment requires 1–5 legs' unless legs.is_a?(Array) && legs.size.between?(1, 5)

      total = legs.each_with_index.sum do |leg, index|
        raise ConfigurationError, 'Split legs must be objects' unless leg.is_a?(Hash)

        SplitPaymentRules.leg!(leg, "legs[#{index}]")
        minor!(leg['amount']).to_i
      end
      raise ConfigurationError, 'Split leg amounts must equal totalAmount' unless total == data['totalAmount'].to_i

      OrderDetails.check!(data, 'A split payment')
      client.request('POST', "#{BASE}/split", body: data, idempotency_key: Client.idempotency_key!(idempotency_key))
    end

    # @return [Hash] Current split-session status envelope.
    def get_split(split_id)
      client.request('GET', "#{BASE}/split/#{identifier!(split_id)}", signed: false)
    end

    # Split payments, newest first. Filters: LIST_SPLIT_PAYMENTS_FILTERS; status and currency take a
    # value or a list, limit is 1–100 and after is the pageInfo.endCursor of the previous page.
    def list_splits(**filters)
      client.request('GET', "#{BASE}/split", query: SplitPaymentRules.list_query!(filters), signed: false)
    end

    # Refund a split session using the documented partial/full amount in minor units.
    def refund_split(split_id, amount:, idempotency_key:, reason: nil)
      body = { 'amount' => minor!(amount) }
      body['reason'] = reason!(reason) unless reason.nil?
      client.request('POST', "#{BASE}/split/#{identifier!(split_id)}/refund", body: body,
                                                                              idempotency_key: Client.idempotency_key!(idempotency_key))
    end

    private

    def action_path(payment_id, action_id, operation)
      "#{BASE}/#{identifier!(payment_id)}/actions/#{identifier!(action_id)}/#{operation}"
    end

    def promissory_notes_path(payment_id)
      "#{BASE}/#{identifier!(payment_id)}/promissory-notes"
    end

    def identifier!(value)
      raise ConfigurationError, 'Invalid resource identifier' unless value.is_a?(String) && value.match?(/\A[a-zA-Z0-9_-]{1,256}\z/)

      value
    end

    def minor!(value)
      Money.minor(value)
    end

    def currency!(value)
      raise ConfigurationError, 'Currency must be a three-letter uppercase code' unless value.is_a?(String) && value.match?(/\A[A-Z]{3}\z/)
    end

    def reason!(value)
      raise ConfigurationError, 'Reason must be a string of at most 500 characters' unless value.is_a?(String) && value.size <= 500

      value
    end

    def text!(value)
      unless value.is_a?(String) && !value.strip.empty? && value.bytesize <= 255 && !value.match?(/[\x00-\x1f\x7f]/)
        raise ConfigurationError, 'Reference must be a bounded nonempty string'
      end

      value
    end

    def normalize!(body)
      raise ConfigurationError, 'Payment body must be an object' unless body.is_a?(Hash)

      JSON.parse(JsonBody.dump(body))
    end

    def payment_body!(body)
      data = normalize!(body)
      raise ConfigurationError, 'Removed amount field; use amount in integer minor units' if %w[price paidPrice].any? { |key| data.key?(key) }

      minor!(data['amount'])
      currency!(data['currency'])
      text!(data['orderId'])
      validate_callback!(data['callbackUrl']) if data.key?('callbackUrl')
      raise ConfigurationError, 'preauth must be a JSON boolean' if data.key?('preauth') && ![true, false].include?(data['preauth'])

      validate_basket!(data['basketItems'], data['amount']) if data.key?('basketItems')
      data['enabledInstallments'] = EnabledInstallments.check!(data['enabledInstallments']) if data.key?('enabledInstallments')
      data
    end

    def sellers!(sellers, amount)
      raise ConfigurationError, 'Marketplace intent requires a nonempty sellers array' unless sellers.is_a?(Array) && !sellers.empty?

      total = sellers.each_with_index.sum do |seller, index|
        raise ConfigurationError, "sellers[#{index}] must be an object" unless seller.is_a?(Hash)

        text!(seller['subDealerId'])
        Money.minor(seller['amountMinor'], positive: false).to_i
      end
      raise ConfigurationError, 'sellers[].amountMinor must add up to amount' unless total == amount.to_i
    end

    def validate_callback!(url)
      uri = URI.parse(url)
      raise ConfigurationError, 'callbackUrl must use HTTPS' unless uri.is_a?(URI::HTTPS) && uri.host && !uri.userinfo && !uri.fragment && url.bytesize <= 2048
    rescue URI::InvalidURIError, TypeError
      raise ConfigurationError, 'Invalid callbackUrl', cause: nil
    end

    def validate_basket!(items, amount)
      raise ConfigurationError, 'basketItems must be a nonempty array' unless items.is_a?(Array) && !items.empty?

      total = items.sum do |item|
        raise ConfigurationError, 'Basket items must be objects' unless item.is_a?(Hash)

        minor!(item['price']).to_i
      end
      raise ConfigurationError, 'Basket total must equal amount' unless total == amount.to_i
    end
  end
end
