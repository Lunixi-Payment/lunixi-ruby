# frozen_string_literal: true

module Lunixi
  # Insurance (/api/v1/insurance, product INSURANCE_SERVICE): offer, sell and service insurance for your
  # basket items, and submit leads for the types sold by request only.
  #
  # Every call is signed, reads included (401 AUTH_HEADERS_MISSING unsigned, 403 PRODUCT_NOT_ENABLED
  # without the product). The key decides the environment. create_order, confirm_payment, issue_policy,
  # cancel_order, refund_premium and create_lead require an Idempotency-Key (8–200 printable ASCII,
  # checked before sending); create_quote and bind_payment take one optionally.
  #
  # Request fields and filters are checked before anything is sent (the gateway rejects an unknown field
  # with 400). The field rules of an insurance type's own object (insured, tickets ...) are not repeated
  # here: a violation comes back as 422 insurance.validation.invalid with every
  # details.errors[{ field, reason }] at once. Amounts are canonical minor-unit strings.
  #
  # Answers are the envelope's data; lists return a Lunixi::ListPage; policy files are frozen bytes.
  class Insurance
    BASE = '/api/v1/insurance'
    PDF_ACCEPT = 'application/pdf, application/json'
    CSV_ACCEPT = 'text/csv, application/json'

    # consent for create_order: the quote option's terms unchanged and the moment the buyer accepted
    # them (a Time or an ISO 8601 string with a time zone, not in the future).
    def self.consent_from_quote(option, accepted_at)
      terms = option.is_a?(Hash) ? option['terms'] : nil
      raise ConfigurationError, "The quote option has no 'terms': pass an option returned by create_quote or get_quote." unless terms.is_a?(Hash)

      { 'termsVersion' => RouteValue.text!(terms['version'], 'terms.version'),
        'termsSha256' => RouteValue.text!(terms['sha256'], 'terms.sha256'),
        'acceptedAt' => RouteValue.iso_time!(accepted_at, 'acceptedAt') }
    end

    # The premium basket item for a payment that collects the premium of an order (premiumCollectedBy
    # MERCHANT): id = orderId, itemType VIRTUAL, price = premiumAmount. Add it to the payment's basket next
    # to the insured items and add the premium to the payment amount; it carries no insurance field. A
    # PROVIDER order has none.
    def self.premium_basket_item(order, name:, category1:, category2: nil)
      raise ConfigurationError, 'order must be a Hash.' unless order.is_a?(Hash)
      unless order['premiumCollectedBy'] == InsurancePremiumCollectedBy::MERCHANT
        raise ConfigurationError, 'Only an order whose premium you collect (premiumCollectedBy MERCHANT) has a premium basket item.'
      end

      item = { 'id' => RouteValue.text!(order['orderId'], 'order.orderId'),
               'name' => RouteValue.text!(name, 'name'),
               'category1' => RouteValue.text!(category1, 'category1') }
      item['category2'] = RouteValue.text!(category2, 'category2') unless category2.nil? || category2 == ''
      item.merge('itemType' => 'VIRTUAL', 'price' => InsuranceRequest.positive_minor!(order['premiumAmount'], 'order.premiumAmount'))
    end

    def initialize(client)
      @client = client
    end

    # I1. Insurance types offered for a payment's recorded basket; without paymentIntentId the types sold
    # without a basket item. An empty list means insurance is not offered; it is not an error.
    def list_products(**filters)
      read('/products', InsuranceRequest.query!(filters, 'listProducts', %w[currency]))
    end

    # I2. Insurance types offered for basket items before the payment exists (read-only):
    # { currency, insuranceType?, context: { items } }.
    def search_products(request)
      body = RouteRequest.wire_keys!(request, INSURANCE_PRODUCT_SEARCH_FIELDS, 'searchProducts request')
      payload = { 'currency' => RouteValue.currency!(body['currency'], 'currency'), 'context' => context(body, required: true) }
      payload['insuranceType'] = RouteValue.text!(body['insuranceType'], 'insuranceType') if RouteRequest.present?(body['insuranceType'])
      write('/products', payload)
    end

    # I3. Reference codes of one kind (InsuranceReferenceKind), for the type fields that take a code.
    def list_reference_values(kind, **filters)
      path = "/reference/#{RouteRequest.path!(':kind', 'kind' => InsuranceRequest.reference_kind!(kind))}"
      RouteResponse.page(@client.request('GET', BASE + path, query: InsuranceRequest.query!(filters, 'listReferenceValues')))
    end

    def iterate_reference_values(kind, **filters, &block)
      InsuranceRequest.reference_kind!(kind)
      RouteResponse.each_item(filters, block) { |query| list_reference_values(kind, **query) }
    end

    # I4. Prices an insurance type (HTTP 201): { insuranceType, schemaVersion, options[], excludedOptions[] }.
    # The basket is a payment's recorded basket (paymentIntentId) or the items you will send in the payment
    # (context.items), not both; neither for a type sold without a basket item. Every option has its own
    # quoteId, terms and expiresAt. The Idempotency-Key is optional and only correlates traces.
    def create_quote(request, idempotency_key: nil)
      body = RouteRequest.wire_keys!(request, INSURANCE_QUOTE_FIELDS, 'createQuote request')
      payment = RouteRequest.present?(body['paymentIntentId'])
      items = RouteRequest.present?(body['context'])
      if payment && items
        raise ConfigurationError, "Send the basket either as 'paymentIntentId' (a payment that exists) or as 'context.items' (before the " \
                                  'payment), not both. Send neither for an insurance type sold without a basket item.'
      end

      payload = body.merge('insuranceType' => RouteValue.text!(body['insuranceType'], 'insuranceType'),
                           'currency' => RouteValue.currency!(body['currency'], 'currency'))
      payload['paymentIntentId'] = InsuranceRequest.uuid!(body['paymentIntentId'], 'paymentIntentId') if payment
      payload['context'] = context(body, required: true) if items
      merchant_order_id!(payload)
      write('/quotes', RouteRequest.compact(payload), InsuranceRequest.optional_key(idempotency_key))
    end

    # I5. 404 insurance.quote.not_found for an unknown or another merchant's quote.
    def get_quote(quote_id)
      read("/quotes/#{segment(quote_id, 'quoteId')}")
    end

    # I6. Turns a quote option into an order (HTTP 201) and records the buyer's consent; no provider call,
    # no money movement. consent carries the option's terms back unchanged (Insurance.consent_from_quote).
    def create_order(request, idempotency_key: nil)
      key = InsuranceRequest.required_key!(idempotency_key, 'insurance order create')
      body = RouteRequest.wire_keys!(request, INSURANCE_ORDER_FIELDS, 'createOrder request')
      consent = RouteRequest.wire_keys!(body['consent'], INSURANCE_CONSENT_FIELDS, 'consent')
      payload = { 'quoteId' => RouteValue.text!(body['quoteId'], 'quoteId'), 'merchantOrderId' => body['merchantOrderId'],
                  'consent' => { 'termsVersion' => RouteValue.text!(consent['termsVersion'], 'consent.termsVersion'),
                                 'termsSha256' => RouteValue.text!(consent['termsSha256'], 'consent.termsSha256'),
                                 'acceptedAt' => RouteValue.iso_time!(consent['acceptedAt'], 'consent.acceptedAt') } }
      merchant_order_id!(payload)
      write('/orders', RouteRequest.compact(payload), key)
    end

    # I7. Your insurance orders, newest first.
    def list_orders(**filters)
      RouteResponse.page(@client.request('GET', "#{BASE}/orders", query: InsuranceRequest.query!(filters, 'listOrders')))
    end

    def iterate_orders(**filters, &block)
      RouteResponse.each_item(filters, block) { |query| list_orders(**query) }
    end

    # I8. 404 insurance.order.not_found for an unknown or another merchant's order.
    def get_order(order_id)
      read(order_path(order_id))
    end

    # I9. Binds an order to the Lunixi payment that collects its premium. With premiumCollectedBy MERCHANT
    # the payment basket must hold the premium item (Insurance.premium_basket_item); with PROVIDER it must
    # not. Binding the same payment again returns the order. The Idempotency-Key is optional.
    def bind_payment(order_id, payment_intent_id, idempotency_key: nil)
      body = { 'paymentIntentId' => InsuranceRequest.uuid!(payment_intent_id, 'paymentIntentId') }
      write("#{order_path(order_id)}/bind-payment", body, InsuranceRequest.optional_key(idempotency_key))
    end

    # I10. Records a premium you collected outside Lunixi: { externalPaymentId, paidAmount, paidCurrency,
    # paidAt, paymentProvider? }; paidAmount and paidCurrency must equal the order's premium.
    def confirm_payment(order_id, payment, idempotency_key: nil)
      key = InsuranceRequest.required_key!(idempotency_key, 'insurance payment confirmation')
      body = RouteRequest.wire_keys!(payment, INSURANCE_EXTERNAL_PAYMENT_FIELDS, 'payment')
      payload = { 'externalPaymentId' => RouteValue.text!(body['externalPaymentId'], 'payment.externalPaymentId', InsuranceRequest::TEXT_MAX_LENGTH),
                  'paidAmount' => InsuranceRequest.positive_minor!(body['paidAmount'], 'payment.paidAmount'),
                  'paidCurrency' => RouteValue.currency!(body['paidCurrency'], 'payment.paidCurrency'),
                  'paidAt' => RouteValue.iso_time!(body['paidAt'], 'payment.paidAt') }
      if RouteRequest.present?(body['paymentProvider'])
        payload['paymentProvider'] = RouteValue.text!(body['paymentProvider'], 'payment.paymentProvider', InsuranceRequest::CODE_MAX_LENGTH)
      end
      write("#{order_path(order_id)}/confirm-payment", { 'payment' => payload }, key)
    end

    # I11. Requests the policy of an order whose premium you collected outside Lunixi (policyStatus
    # PENDING; the result arrives by webhook). 412 insurance.premium.not_captured before collection.
    def issue_policy(order_id, idempotency_key: nil)
      write("#{order_path(order_id)}/issue-policy", nil, InsuranceRequest.required_key!(idempotency_key, 'insurance policy issue'))
    end

    # I12. Opens a cancellation at the provider for every issued policy (policyStatus CANCEL_PENDING;
    # insurance.policy.cancelled confirms it). It does not refund the premium: call refund_premium after it.
    def cancel_order(order_id, idempotency_key: nil)
      write("#{order_path(order_id)}/cancel", nil, InsuranceRequest.required_key!(idempotency_key, 'insurance order cancel'))
    end

    # I13. Refunds the premium. With a Lunixi payment leave external_refund out (refundStatus PENDING, then
    # insurance.refund.completed); for a premium collected outside Lunixi pass the refund you made:
    # { externalRefundId, refundedAt }. An in-force policy must be cancelled first (409).
    def refund_premium(order_id, external_refund: nil, idempotency_key: nil)
      key = InsuranceRequest.required_key!(idempotency_key, 'insurance premium refund')
      payload = {}
      unless external_refund.nil?
        refund = RouteRequest.wire_keys!(external_refund, INSURANCE_EXTERNAL_REFUND_FIELDS, 'externalRefund')
        payload['externalRefund'] = {
          'externalRefundId' => RouteValue.text!(refund['externalRefundId'], 'externalRefund.externalRefundId', InsuranceRequest::TEXT_MAX_LENGTH),
          'refundedAt' => RouteValue.iso_time!(refund['refundedAt'], 'externalRefund.refundedAt')
        }
      end
      write("#{order_path(order_id)}/refund-premium", payload, key)
    end

    # I14. The policy PDF as frozen bytes, read from the provider on every call while the policy is in
    # force (ISSUED, CANCEL_PENDING); 503 insurance.document.unavailable is temporary.
    def get_policy_document(policy_id)
      policy_file(policy_id, 'document')
    end

    # I21. The provider's premium receipt as PDF bytes; 412 insurance.document.not_supported when the
    # product issues none.
    def get_policy_receipt(policy_id)
      policy_file(policy_id, 'receipt')
    end

    # I22. The provider's certificate of the policy (for example a green card) as PDF bytes; 412
    # insurance.document.not_supported when the product issues none.
    def get_policy_certificate(policy_id)
      policy_file(policy_id, 'certificate')
    end

    # I15. Reconciliation totals by provider connection, currency and premiumCollectedBy. from (inclusive)
    # and to (exclusive) are required, on the order creation time, at most 366 days apart.
    def get_reconciliation_summary(**filters)
      read('/reconciliation/summary', InsuranceRequest.query!(filters, 'getReconciliationSummary', %w[from to]))
    end

    # I16. The orders and policies behind the summary for the same filter, newest first.
    def list_reconciliation_orders(**filters)
      query = InsuranceRequest.query!(filters, 'listReconciliationOrders', %w[from to])
      RouteResponse.page(@client.request('GET', "#{BASE}/reconciliation/orders", query: query))
    end

    def iterate_reconciliation_orders(**filters, &block)
      RouteResponse.each_item(filters, block) { |query| list_reconciliation_orders(**query) }
    end

    # I17. The reconciliation report as CSV: a Lunixi::InsuranceReconciliationExport (data bytes,
    # truncated?, next_cursor, aborted?).
    def export_reconciliation(**filters)
      query = InsuranceRequest.query!(filters, 'exportReconciliation', %w[from to])
      InsuranceRequest.export(@client.request('GET', "#{BASE}/reconciliation/export", query: query, binary: true, accept: CSV_ACCEPT))
    end

    # I18. Submits a lead (HTTP 201) for a type sold by request only: no premium, order, policy or
    # document. status SUBMITTED (then insurance.lead.submitted) or UNKNOWN (not sent again). A provider
    # refusal is 422 insurance.lead.rejected; a type or connection without leads 412
    # insurance.type.not_available. The Idempotency-Key is required.
    def create_lead(request, idempotency_key: nil)
      key = InsuranceRequest.required_key!(idempotency_key, 'insurance lead submit')
      body = RouteRequest.wire_keys!(request, INSURANCE_LEAD_FIELDS, 'createLead request')
      payload = body.merge('insuranceType' => RouteValue.text!(body['insuranceType'], 'insuranceType', InsuranceRequest::CODE_MAX_LENGTH))
      payload['note'] = InsuranceRequest.lead_note!(body['note']) if body.key?('note')
      payload.delete('note') if payload['note'] == ''
      write('/leads', payload, key)
    end

    # I19. Your leads, newest first; personal data is masked in requestMasked.
    def list_leads(**filters)
      RouteResponse.page(@client.request('GET', "#{BASE}/leads", query: InsuranceRequest.query!(filters, 'listLeads')))
    end

    def iterate_leads(**filters, &block)
      RouteResponse.each_item(filters, block) { |query| list_leads(**query) }
    end

    # I20. 404 insurance.lead.not_found for an unknown or another merchant's lead.
    def get_lead(lead_id)
      read("/leads/#{segment(lead_id, 'leadId')}")
    end

    def inspect
      '#<Lunixi::Insurance>'
    end

    private

    def read(path, query = {})
      RouteResponse.unwrap(@client.request('GET', BASE + path, query: query))
    end

    def write(path, body, key = nil)
      RouteResponse.unwrap(@client.request('POST', BASE + path, body: body, idempotency_key: key))
    end

    def policy_file(policy_id, file)
      @client.request('GET', "#{BASE}/policies/#{segment(policy_id, 'policyId')}/#{file}", binary: true, accept: PDF_ACCEPT)
    end

    def context(body, required:)
      raise ConfigurationError, "'context.items' is required." if required && !RouteRequest.present?(body['context'])

      InsuranceRequest.context!(body['context'])
    end

    def merchant_order_id!(payload)
      if RouteRequest.present?(payload['merchantOrderId'])
        payload['merchantOrderId'] = RouteValue.text!(payload['merchantOrderId'], 'merchantOrderId', InsuranceRequest::TEXT_MAX_LENGTH)
      else
        payload.delete('merchantOrderId')
      end
    end

    def order_path(order_id)
      "/orders/#{segment(order_id, 'orderId')}"
    end

    def segment(value, field)
      RouteRequest.path!(":#{field}", field => value)
    end
  end
end
