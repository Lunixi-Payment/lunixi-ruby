# frozen_string_literal: true

module Lunixi
  # Marketplace (client.marketplace): split charges across sub-dealers, the sub-dealer lifecycle,
  # commissions, payouts and the audit log.
  #
  # Split charges (/api/v1/payments/marketplace) are signed per request and take an optional
  # Idempotency-Key (the payment key rule: 16–128 printable ASCII). A split is aggregate per seller: group
  # the basket by vendor and pass one leg per sub-dealer, { subDealerId, amountMinor, scenario? }; the legs
  # must add up to amount. Dealer, commission, payout and audit routes (/api/v1/marketplace) carry the
  # access token only.
  #
  # Card data (card number, expiry, security code) is sent as given and never logged or put in an error
  # message; a direct card charge is PCI DSS SAQ-D scope, so most marketplaces use create_checkout_intent
  # (hosted form).
  #
  # Amounts are canonical minor-unit strings. Entity calls return the envelope's data; lists return a
  # Lunixi::ListPage.
  class Marketplace
    REMOVED_AMOUNT_FIELDS = %w[price paidPrice].freeze

    # Onboarding URL of an onboarding_token answer: its url, else the hosted wizard with its token.
    def self.onboarding_url(link, base = MARKETPLACE_DEALER_ONBOARDING_HOSTED_BASE)
      return link['url'] if link.is_a?(Hash) && link['url'].is_a?(String) && !link['url'].empty?

      token = link.is_a?(Hash) && link['token'].is_a?(String) ? link['token'] : ''
      "#{base.to_s.sub(%r{/+\z}, '')}/m/#{URI.encode_www_form_component(token).gsub('+', '%20')}"
    end

    def initialize(client)
      @routes = RouteTable.new(client, MARKETPLACE_ROUTES)
    end

    # Hosted-form split checkout (POST /payments/marketplace/intents): the intent body (amount, currency,
    # orderId, callbackUrl, basketItems ...) plus the seller legs. Returns the answer as it came (token,
    # checkoutFormContent, paymentId ...); an answer without a token or a form (a seller not eligible
    # under ALL_OR_NOTHING) raises ApiError instead of leaving the buyer on an empty page. The same route
    # as payments.create_marketplace_intent, which takes the legs inside the body.
    def create_checkout_intent(request, sellers, multi_seller_policy: MarketplaceMultiSellerPolicy::ALL_OR_NOTHING, idempotency_key: nil)
      body = split_body(payload!(request, 'create_checkout_intent request'), sellers, multi_seller_policy)
      response = @routes.call('createCheckoutIntent', body: body, idempotency_key: idempotency_key)
      intent = RouteResponse.merge_root(response)
      return response if RouteResponse.text(intent['token']) || RouteResponse.text(intent['checkoutFormContent'])

      raise ApiError.new(status: intent['statusCode'].is_a?(Integer) ? intent['statusCode'] : 0, code: intent['code'],
                         request_id: intent['requestId'], message: 'The marketplace checkout intent did not return a token or a checkout form.')
    end

    # Direct split card charge from a raw body (amount, currency, orderId, card, buyer, billingAddress,
    # basketItems, sellers, multiSellerPolicy, preauth? ...): POST /payments/marketplace/3d with
    # three_ds: true, /2d otherwise. Prefer charge_marketplace_card2d / charge_marketplace_card3d, which
    # check the body and the legs.
    def charge_marketplace_card(payload, three_ds: false, idempotency_key: nil)
      raise ConfigurationError, "'three_ds' must be true or false." unless [true, false].include?(three_ds)

      body = payload!(payload, 'charge_marketplace_card payload')
      charge_amount!(body)
      @routes.call(three_ds ? 'chargeMarketplaceCard3d' : 'chargeMarketplaceCard2d', body: body, idempotency_key: idempotency_key)
    end

    # Split card charge without 3-D Secure: the card payment body plus the seller legs.
    def charge_marketplace_card2d(request, sellers, multi_seller_policy: MarketplaceMultiSellerPolicy::ALL_OR_NOTHING, idempotency_key: nil)
      charge_marketplace_card(charge_body(request, sellers, multi_seller_policy), three_ds: false, idempotency_key: idempotency_key)
    end

    # Split card charge with 3-D Secure: the card payment body plus the seller legs.
    def charge_marketplace_card3d(request, sellers, multi_seller_policy: MarketplaceMultiSellerPolicy::ALL_OR_NOTHING, idempotency_key: nil)
      charge_marketplace_card(charge_body(request, sellers, multi_seller_policy), three_ds: true, idempotency_key: idempotency_key)
    end

    # { legalName, taxId?, dealerType?, categoryCode?, email?, externalRef? }. The dealer then onboards
    # itself (KYC, IBAN, contract) before it is ACTIVE.
    def create_dealer(request)
      body = RouteRequest.wire_hash!(request, 'createDealer request')
      RouteValue.one_of!(body['dealerType'], MarketplaceDealerType::ALL, 'dealerType') if body.key?('dealerType')
      @routes.data('createDealer', body: body)
    end

    # Several dealers at once (an import); each row as in create_dealer.
    def bulk_create_dealers(dealers)
      raise ConfigurationError, 'bulk_create_dealers needs a non-empty array of dealers.' unless dealers.is_a?(Array) && !dealers.empty?

      rows = dealers.each_with_index.map { |dealer, index| RouteRequest.wire_hash!(dealer, "dealers[#{index}]") }
      @routes.data('bulkCreateDealers', body: { 'dealers' => rows })
    end

    # Filters: status, search, limit, offset.
    def list_dealers(**filters)
      @routes.page('listDealers', query: filters)
    end

    def get_dealer(dealer_id)
      @routes.data('getDealer', params: { 'dealerId' => dealer_id })
    end

    def update_dealer_status(dealer_id, status)
      RouteValue.one_of!(status, MarketplaceDealerStatus::ALL, 'status')
      @routes.data('updateDealerStatus', params: { 'dealerId' => dealer_id }, body: { 'status' => status })
    end

    # Self-onboarding link: { token, url, ... } (token also starts the embedded onboarding SDK).
    # Lunixi::Marketplace.onboarding_url(link) gives the URL.
    def onboarding_token(dealer_id)
      RouteResponse.merge_root(@routes.call('onboardingToken', params: { 'dealerId' => dealer_id }))
    end

    # Onboarding / application status.
    def dealer_application(dealer_id)
      @routes.data('dealerApplication', params: { 'dealerId' => dealer_id })
    end

    def submit_dealer_application(dealer_id, payload = {})
      @routes.data('submitDealerApplication', params: { 'dealerId' => dealer_id }, body: payload)
    end

    # Commission / terms definition.
    def set_dealer_terms(dealer_id, payload)
      @routes.data('setDealerTerms', params: { 'dealerId' => dealer_id }, body: payload)
    end

    # Signature / contract acceptance.
    def sign_dealer_contract(dealer_id, payload = {})
      @routes.data('signDealerContract', params: { 'dealerId' => dealer_id }, body: payload)
    end

    def activate_dealer(dealer_id)
      @routes.data('activateDealer', params: { 'dealerId' => dealer_id })
    end

    # A KYC outcome, when you run the dealer's KYC yourself.
    def record_dealer_kyc_result(dealer_id, payload)
      @routes.data('recordDealerKycResult', params: { 'dealerId' => dealer_id }, body: payload)
    end

    # Filters: status, subDealerId, days, limit.
    def payout_ledger(**filters)
      @routes.page('payoutLedger', query: filters)
    end

    # Filters: status, subDealerId, limit.
    def transactions(**filters)
      @routes.page('transactions', query: filters)
    end

    # Filter: limit.
    def commission_rules(**filters)
      @routes.page('commissionRules', query: filters)
    end

    def upsert_commission_rule(rule)
      @routes.data('upsertCommissionRule', body: rule)
    end

    # A dry run of a rule's effect.
    def preview_commission_rule(rule)
      @routes.data('previewCommissionRule', body: rule)
    end

    # The effective commission of a dealer (and category) at a month-to-date volume (mtd_volume_minor, a
    # minor-unit string).
    def resolve_commission(sub_dealer_id, category_code: nil, mtd_volume_minor: nil)
      query = RouteRequest.compact('subDealerId' => RouteValue.text!(sub_dealer_id, 'subDealerId'),
                                   'categoryCode' => RouteValue.optional_text(category_code, 'categoryCode'), 'mtdVolumeMinor' => mtd_volume_minor)
      @routes.data('resolveCommission', query: query)
    end

    # A manual payout: { subDealerId, amountMinor, currency, reference?, ... }.
    def create_payout(payload)
      body = RouteRequest.wire_hash!(payload, 'createPayout payload')
      WireMoney.wire_minor!(body['amountMinor'], 'amountMinor') if body.key?('amountMinor')
      @routes.data('createPayout', body: body)
    end

    # { paidAt?, reference?, ... }.
    def mark_payout_paid(payout_id, payload = {})
      @routes.data('markPayoutPaid', params: { 'payoutId' => payout_id }, body: payload)
    end

    def bulk_mark_payouts_paid(payout_ids, extra = {})
      raise ConfigurationError, 'bulk_mark_payouts_paid needs a non-empty array of payout ids.' unless payout_ids.is_a?(Array) && !payout_ids.empty?

      ids = payout_ids.each_with_index.map { |id, index| RouteValue.text!(id, "payoutIds[#{index}]") }
      @routes.data('bulkMarkPayoutsPaid', body: RouteRequest.wire_hash!(extra, 'bulk_mark_payouts_paid extra').merge('payoutIds' => ids))
    end

    # The append-only, hash-chained audit log; filters limit, type.
    def audit_log(**filters)
      @routes.page('auditLog', query: filters)
    end

    # Verifies the integrity of the hash chain.
    def verify_audit_log
      @routes.data('verifyAuditLog')
    end

    def inspect
      '#<Lunixi::Marketplace>'
    end

    private

    # A request Hash (or an object with to_h) as plain JSON data with String keys at every level.
    def payload!(value, label)
      value = value.to_h if !value.is_a?(Hash) && !value.is_a?(Array) && !value.nil? && value.respond_to?(:to_h)
      raise ConfigurationError, "#{label} must be a Hash." unless value.is_a?(Hash)

      JSON.parse(JsonBody.dump(value))
    end

    # The charge body of charge_marketplace_card2d / 3d: the commercial context is required.
    def charge_body(request, sellers, multi_seller_policy)
      body = payload!(request, 'marketplace charge request')
      missing = MARKETPLACE_CHARGE_REQUIRED_FIELDS.reject { |field| RouteRequest.present?(body[field]) }
      raise ConfigurationError, "A marketplace card charge requires #{missing.join(', ')}." unless missing.empty?
      raise ConfigurationError, 'A marketplace card charge requires at least one basket item.' unless body['basketItems'].is_a?(Array)

      split_body(body, sellers, multi_seller_policy)
    end

    # Adds the seller legs and the policy; the legs must add up to amount.
    def split_body(body, sellers, multi_seller_policy)
      if body.key?('sellers') || body.key?('multiSellerPolicy')
        raise ConfigurationError, 'Pass the seller legs and multi_seller_policy as arguments, not in the request body.'
      end

      charge_amount!(body)
      RouteValue.one_of!(multi_seller_policy, MarketplaceMultiSellerPolicy::ALL, 'multiSellerPolicy')
      raise ConfigurationError, 'A marketplace split requires at least one seller leg.' unless sellers.is_a?(Array) && !sellers.empty?

      legs = sellers.each_with_index.map { |seller, index| seller_leg(seller, index) }
      total = legs.sum { |leg| Integer(leg['amountMinor'], 10) }
      unless total == Integer(body['amount'], 10)
        raise ConfigurationError, "The seller legs add up to #{total}, not to amount #{body['amount']}; the gateway refuses any other total."
      end

      body.merge('sellers' => legs, 'multiSellerPolicy' => multi_seller_policy)
    end

    def seller_leg(seller, index)
      label = "sellers[#{index}]"
      leg = RouteRequest.wire_keys!(seller.is_a?(Hash) ? seller : payload!(seller, label), MARKETPLACE_SELLER_FIELDS, label)
      out = { 'subDealerId' => RouteValue.text!(leg['subDealerId'], "#{label}.subDealerId"),
              'amountMinor' => WireMoney.wire_minor!(leg['amountMinor'], "#{label}.amountMinor") }
      if leg.key?('scenario')
        raise ConfigurationError, "'#{label}.scenario' must be a Hash." unless leg['scenario'].is_a?(Hash)

        out['scenario'] = leg['scenario']
      end
      out
    end

    # amount (the basket total) is a positive minor-unit string; price / paidPrice are removed fields;
    # preauth is a boolean; the other money members are canonical.
    def charge_amount!(body)
      sent = REMOVED_AMOUNT_FIELDS.select { |field| body.key?(field) }
      raise ConfigurationError, "#{sent.join(', ')}: removed from the payment body; send the amount only in 'amount' (minor units)." unless sent.empty?

      WireMoney.wire_minor!(body['amount'], 'amount')
      raise ConfigurationError, "'preauth' must be true or false." if body.key?('preauth') && ![true, false].include?(body['preauth'])

      Money.validate_fields(body)
    end
  end
end
