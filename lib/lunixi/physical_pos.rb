# frozen_string_literal: true

module Lunixi
  # Physical POS: payments on your card terminals, transactions, reports, end-of-day runs and results
  # (/api/v1/physical-pos). Every call is signed; the signing key decides the environment (a TEST key
  # can read, but every payment write is 403 physical_pos.environment.test_key_read_only). Payment
  # writes need the physical_pos:payments scope; reads physical_pos:view or physical_pos:payments.
  #
  # Card data is never sent: the card is read on the device. A field that looks like card data (pan,
  # cardNumber, cvv, expiry …) or a card number in merchantReference, an item name / tax group or a
  # free-text filter raises PhysicalPosCardDataRejectedError before anything is sent; any other unknown
  # field raises ConfigurationError. Body and filter keys are the wire names (String or Symbol;
  # snake_case is accepted too). Amounts are canonical minor-unit strings ("4500"); counts and rates
  # are numbers.
  #
  # A payment write is asynchronous: the answer means "accepted", not "paid". Follow the outcome with
  # the physical_pos.payment.* webhooks or get_payment. A payment under manual review is resolved in
  # the panel only.
  #
  # Idempotency: store the key first, then call.
  #
  #   key = Lunixi::PhysicalPos.new_idempotency_key
  #   order.update!(pos_key: key)                               # your storage
  #   begin
  #     lunixi.physical_pos.create_payment(request, idempotency_key: key)
  #   rescue Lunixi::PhysicalPosOutcomeUnknownError
  #     # the payment may exist: call again later with the SAME key
  #   end
  #
  # A new key for the same payment can charge the card twice. For a SALE also send merchantReference
  # with allowDuplicateReference: false; the gateway then refuses a second sale while one with that
  # reference is unresolved (physical_pos.payment.previous_outcome_unknown).
  class PhysicalPos
    NEW_PAYMENT = ->(replayed) { replayed ? 200 : 202 }
    OK = ->(_replayed) { 200 }

    # A new Idempotency-Key (UUID v4). Store it with your order before you call.
    def self.new_idempotency_key
      PhysicalPosIdentifiers.new_idempotency_key
    end

    # Verifies (signature, event id, timestamp) and reads a physical_pos.* webhook from the raw body,
    # the headers and your webhook secret (or a WebhookVerifier). See PhysicalPosWebhook.parse.
    def self.parse_webhook_event(raw_body, headers, secret_or_verifier, tolerance: 300)
      PhysicalPosWebhook.parse(raw_body, headers, secret_or_verifier, tolerance: tolerance)
    end

    def initialize(gateway)
      @gateway = gateway
    end

    # Starts a payment on a device: SALE, PREAUTH_OPEN or REFUND_UNMATCHED (POST /payments). target is
    # exactly one of { deviceId }, { vendorCode, serialNumber } or { externalRef }; items carry a
    # taxGroupCode per line.
    #
    # instrument is CARD (default) or a provider-collected card such as MEAL_CARD; for those send
    # interaction (INSTRUMENT_READ: the device reads the card, CODE_DISPLAY: the device shows the
    # provider's QR / short code) and, when the terminal has several provider rows, terminalProviderId
    # (a list_terminal_providers row id). Leave both out for CARD.
    #
    # idempotency_key is required. Returns a PhysicalPosWriteResult: 202 with paymentStatus NOT_STARTED
    # for a new payment, 200 with replayed true when the same key and body were sent before (the
    # payment's current view). Raises PhysicalPosOutcomeUnknownError when the outcome is unknown.
    def create_payment(request, idempotency_key: nil)
      key = PhysicalPosIdentifiers.required_idempotency_key!(idempotency_key, 'a physical POS payment')
      body = PhysicalPosRequest.body!(request, PHYSICAL_POS_REQUEST_FIELDS['createPayment'], 'createPayment request')
      @gateway.payment_write('/payments', body, key, NEW_PAYMENT)
    end

    # Reverses an approved payment (POST /payments/{paymentId}/reversals): VOID, REFUND (by amountMinor
    # or by items: [{ lineNo, quantityMilli }]), PREAUTH_CLOSE or PREAUTH_CANCEL. The reversal is a new
    # child payment (originalPaymentId = payment_id) followed like any payment. idempotency_key is
    # required; same result and errors as create_payment.
    def create_reversal(payment_id, request, idempotency_key: nil)
      path = "/payments/#{PhysicalPosIdentifiers.path_id(payment_id, 'paymentId')}/reversals"
      key = PhysicalPosIdentifiers.required_idempotency_key!(idempotency_key, 'a physical POS reversal')
      body = PhysicalPosRequest.body!(request, PHYSICAL_POS_REQUEST_FIELDS['createReversal'], 'createReversal request')
      @gateway.payment_write(path, body, key, NEW_PAYMENT)
    end

    # Cancels a payment before its start command reaches the device (POST /payments/{paymentId}/cancel,
    # 200). Read payment['paymentStatus']: only EXPIRED with statusReason
    # MERCHANT_CANCELLED_BEFORE_DISPATCH means it was cancelled; a payment already in a final state
    # comes back unchanged with replayed true. To undo an approved sale use a reversal. Cancelling is
    # idempotent, so the key is optional (a new UUID when nil).
    def cancel_payment(payment_id, idempotency_key: nil)
      path = "/payments/#{PhysicalPosIdentifiers.path_id(payment_id, 'paymentId')}/cancel"
      @gateway.payment_write(path, {}, PhysicalPosIdentifiers.idempotency_key_or_new(idempotency_key), OK)
    end

    # One payment with its items and refund items (GET /payments/{paymentId}).
    def get_payment(payment_id)
      @gateway.record('GET', "/payments/#{PhysicalPosIdentifiers.path_id(payment_id, 'paymentId')}", 'payment')
    end

    # Payments, newest first (GET /payments). Roots and reversals are in one list; items and
    # refundItems are empty here (read one payment for them). merchantReference finds a payment after
    # an unknown outcome.
    def list_payments(**filters)
      @gateway.page('/payments', PhysicalPosFilters.query!(filters, 'listPayments'))
    end

    def iterate_payments(**filters, &block)
      PhysicalPosResponses.each_item(filters, block) { |query| list_payments(**query) }
    end

    # Transaction trees (root payment + its reversals), newest first (GET /transactions).
    def list_transactions(**filters)
      @gateway.page('/transactions', PhysicalPosFilters.query!(filters, 'listTransactions'))
    end

    def iterate_transactions(**filters, &block)
      PhysicalPosResponses.each_item(filters, block) { |query| list_transactions(**query) }
    end

    # The tree of a root or child payment with its timeline (GET /transactions/{paymentId}).
    def get_transaction(payment_id)
      @gateway.record('GET', "/transactions/#{PhysicalPosIdentifiers.path_id(payment_id, 'paymentId')}", 'transaction')
    end

    # Payments with an unknown outcome or under manual review (GET /transactions/ambiguous).
    def list_ambiguous_payments(**filters)
      @gateway.page('/transactions/ambiguous', PhysicalPosFilters.query!(filters, 'listAmbiguousPayments'))
    end

    def iterate_ambiguous_payments(**filters, &block)
      PhysicalPosResponses.each_item(filters, block) { |query| list_ambiguous_payments(**query) }
    end

    # Sale / refund / void counts and amounts with net per currency (GET /reports/sales-summary).
    # dateFrom / dateTo are business days (YYYY-MM-DD, Europe/Istanbul); groupBy DAY, STORE, DEVICE or
    # INSTRUMENT.
    def get_sales_summary(**filters)
      @gateway.data('GET', '/reports/sales-summary', query: PhysicalPosFilters.query!(filters, 'getSalesSummary'))
    end

    # Tax breakdown with refunds and voids deducted (GET /reports/tax-summary).
    def get_tax_summary(**filters)
      @gateway.data('GET', '/reports/tax-summary', query: PhysicalPosFilters.query!(filters, 'getTaxSummary'))
    end

    # End-of-day results per bank line, with the reported / system / difference totals (GET /settlements).
    def list_settlements(**filters)
      @gateway.page('/settlements', PhysicalPosFilters.query!(filters, 'listSettlements'))
    end

    def iterate_settlements(**filters, &block)
      PhysicalPosResponses.each_item(filters, block) { |query| list_settlements(**query) }
    end

    # Starts end-of-day (batch close) on a device (POST /devices/{deviceId}/settlement,
    # physical_pos:payments). End-of-day cannot be undone. The answer means "accepted": the device
    # reports the result later; follow it with get_settlement_run or list_settlements.
    #
    # Returns a PhysicalPosWriteResult (result['run'], 202 new / 200 replay). Pass the key you stored,
    # or nil for a new UUID (returned as idempotency_key; after an unknown outcome call again with it).
    # A TEST key is refused with 403 physical_pos.environment.test_key_read_only.
    def start_settlement(device_id, idempotency_key: nil)
      path = "/devices/#{PhysicalPosIdentifiers.path_id(device_id, 'deviceId')}/settlement"
      @gateway.keyed_write(path, {}, idempotency_key, NEW_PAYMENT)
    end

    # End-of-day runs started by Lunixi (manual and scheduled), newest first (GET /settlement-runs).
    # Filters: deviceId, source (MANUAL_API, MANUAL_PANEL, SCHEDULED), runStatus (PENDING, STARTED,
    # SKIPPED, FAILED), createdFrom / createdTo, includeTotal.
    def list_settlement_runs(**filters)
      @gateway.page('/settlement-runs', PhysicalPosFilters.query!(filters, 'listSettlementRuns'))
    end

    def iterate_settlement_runs(**filters, &block)
      PhysicalPosResponses.each_item(filters, block) { |query| list_settlement_runs(**query) }
    end

    # One end-of-day run with its command status and result state (GET /settlement-runs/{runId}).
    def get_settlement_run(run_id)
      @gateway.record('GET', "/settlement-runs/#{PhysicalPosIdentifiers.path_id(run_id, 'runId')}", 'run')
    end

    def inspect
      '#<Lunixi::PhysicalPos>'
    end
  end
end
