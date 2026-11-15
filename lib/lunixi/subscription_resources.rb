# frozen_string_literal: true

module Lunixi
  # subscriptions.plans: the templates a subscription is created against.
  class SubscriptionPlans
    def initialize(routes)
      @routes = routes
    end

    # { productId, code, name, price, currency, billing, description?, trialPeriodDays?,
    # maxDunningAttempts?, dunningScheduleDays?, gracePeriodDays?, metadata? }. price is a minor-unit
    # string ("0" for a free plan); billing is { frequency, interval?, byMonthDay?, byWeekDay?, timezone?,
    # lastDayOfMonthFix?, count? } (interval defaults to 1).
    def create(request, idempotency_key: nil)
      @routes.data('plans.create', body: SubscriptionRules.plan!(request), idempotency_key: idempotency_key)
    end

    def get(plan_id)
      @routes.data('plans.get', params: { 'planId' => plan_id })
    end

    # Filters: productId, includeArchived, pageSize, pageToken.
    def list(**filters)
      @routes.token_page('plans.list', query: filters)
    end

    def iterate(**filters, &block)
      RouteRequest.each_item(filters, block, :pageToken) { |query| list(**query) }
    end

    # Price, billing, metadata ...; a price is a minor-unit string.
    def update(plan_id, changes)
      @routes.data('plans.update', params: { 'planId' => plan_id }, body: changes)
    end

    def archive(plan_id)
      @routes.data('plans.archive', params: { 'planId' => plan_id })
    end

    def translations(plan_id)
      @routes.data('plans.translations', params: { 'planId' => plan_id })
    end

    def upsert_translation(plan_id, locale, translation)
      @routes.data('plans.upsertTranslation', params: { 'planId' => plan_id, 'locale' => locale }, body: translation)
    end
  end

  # subscriptions.customers, upserted by your own externalId (one stable customer per user).
  class SubscriptionCustomers
    def initialize(routes)
      @routes = routes
    end

    # { externalId, email?, name?, phone?, locale?, metadata? }.
    def upsert(request, idempotency_key: nil)
      @routes.data('customers.upsert', body: request, idempotency_key: idempotency_key)
    end

    def get(customer_id)
      @routes.data('customers.get', params: { 'customerId' => customer_id })
    end

    def get_by_external_id(external_id)
      @routes.data('customers.getByExternalId', params: { 'externalId' => external_id })
    end

    # Filters: search, includeArchived, pageSize, pageToken.
    def list(**filters)
      @routes.token_page('customers.list', query: filters)
    end

    def iterate(**filters, &block)
      RouteRequest.each_item(filters, block, :pageToken) { |query| list(**query) }
    end

    def credit_balance(customer_id)
      @routes.data('customers.creditBalance', params: { 'customerId' => customer_id })
    end

    # Grants or deducts credit: { amountMinor, currency, reason, type, ... } (amountMinor a minor-unit
    # string).
    def adjust_credit(customer_id, adjustment)
      @routes.data('customers.adjustCredit', params: { 'customerId' => customer_id }, body: adjustment)
    end

    def archive(customer_id)
      @routes.data('customers.archive', params: { 'customerId' => customer_id })
    end
  end

  # subscriptions.cards: saved cards for automatic charges. A card is added from the checkout SDK's
  # paymentMethodToken; a card number or security code is never sent (the field is refused and the error
  # names only the field).
  class SubscriptionCards
    def initialize(routes)
      @routes = routes
    end

    # { customerId, paymentMethodToken, brand?, last4?, bin?, expireMonth?, expireYear?, cardholderName?,
    # isDefault?, nickname?, verificationMode?, supportedCurrencies? }.
    def add(request, idempotency_key: nil)
      @routes.data('cards.add', body: SubscriptionRules.card!(request), idempotency_key: idempotency_key)
    end

    def get(card_id)
      @routes.data('cards.get', params: { 'cardId' => card_id })
    end

    # A customer's cards.
    def list(customer_id, include_inactive: false, page_token: nil, page_size: nil)
      query = { 'customerId' => RouteRequest.text!(customer_id, 'customerId'), 'includeInactive' => include_inactive,
                'pageToken' => page_token, 'pageSize' => page_size }
      @routes.token_page('cards.list', query: RouteRequest.compact(query))
    end

    def iterate(customer_id, include_inactive: false, page_size: nil, &block)
      filters = RouteRequest.compact(include_inactive: include_inactive, page_size: page_size)
      RouteRequest.each_item(filters, block, :page_token) { |query| list(customer_id, **query) }
    end

    def set_default(card_id)
      @routes.data('cards.setDefault', params: { 'cardId' => card_id })
    end

    def deactivate(card_id, reason: nil)
      @routes.data('cards.deactivate', params: { 'cardId' => card_id },
                                       body: RouteRequest.compact('reason' => RouteRequest.optional_text(reason, 'reason')))
    end

    # Verifies a saved card (a small authorisation or a 3-D check); options as the gateway documents them.
    def verify(card_id, options = {})
      @routes.data('cards.verify', params: { 'cardId' => card_id }, body: options)
    end

    # Card metadata (label, expiry, billing ...); never a card number.
    def update(card_id, changes)
      @routes.data('cards.update', params: { 'cardId' => card_id }, body: changes)
    end
  end

  # subscriptions.invoices: billing history, void and charge retry.
  class SubscriptionInvoices
    def initialize(routes)
      @routes = routes
    end

    # Filters: subscriptionId, status, pageSize, pageToken.
    def list(**filters)
      @routes.token_page('invoices.list', query: filters)
    end

    def iterate(**filters, &block)
      RouteRequest.each_item(filters, block, :pageToken) { |query| list(**query) }
    end

    def get(invoice_id)
      @routes.data('invoices.get', params: { 'invoiceId' => invoice_id })
    end

    def void(invoice_id, reason: nil)
      @routes.data('invoices.void', params: { 'invoiceId' => invoice_id },
                                    body: RouteRequest.compact('reason' => RouteRequest.optional_text(reason, 'reason')))
    end

    def retry_charge(invoice_id, idempotency_key: nil)
      @routes.data('invoices.retryCharge', params: { 'invoiceId' => invoice_id }, idempotency_key: idempotency_key)
    end
  end

  # subscriptions.portal: the customer portal. Embedded: create_sdk_session mints an origin-bound session
  # for the browser portal SDK (origin must be allow-listed). Hosted: create_portal_link returns a link
  # whose token opens the hosted portal (Lunixi::Subscriptions.portal_url(link)); the customer verifies
  # with a one-time code.
  class SubscriptionPortal
    def initialize(routes)
      @routes = routes
    end

    # Returns { portalToken, sessionProof, proofNonce, proofExpiresAt, ... } (the gateway answers at the
    # envelope root); hand those four to the browser.
    def create_sdk_session(customer_id, origin, sdk_mode: nil, portal_link_id: nil)
      RouteRequest.one_of!(sdk_mode, SubscriptionPortalSdkMode::ALL, 'sdkMode') unless sdk_mode.nil? || sdk_mode == ''
      body = RouteRequest.compact('customerId' => RouteRequest.text!(customer_id, 'customerId'), 'origin' => RouteRequest.text!(origin, 'origin'),
                                  'sdkMode' => RouteRequest.optional_text(sdk_mode, 'sdkMode'),
                                  'portalLinkId' => RouteRequest.optional_text(portal_link_id, 'portalLinkId'))
      session = RouteRequest.merge_root(@routes.call('portal.createSdkSession', body: body))
      session['proofNonce'] = session['nonce'] if !session.key?('proofNonce') && session.key?('nonce')
      session['proofExpiresAt'] = session['expiresAt'] if !session.key?('proofExpiresAt') && session.key?('expiresAt')
      session
    end

    # options: allowedPlanIds, defaultPlanId, permissions, sessionDurationMinutes, expiresAt,
    # requireEmailVerification ...
    def create_portal_link(customer_id, options = {})
      body = RouteRequest.wire_hash!(options, 'create_portal_link options').merge('customerId' => RouteRequest.text!(customer_id, 'customerId'))
      @routes.data('portal.createPortalLink', body: body)
    end

    # Filters: customerId, status, limit.
    def list_links(**filters)
      @routes.page('portal.listLinks', query: filters)
    end

    def get_link(link_id)
      @routes.data('portal.getLink', params: { 'linkId' => link_id })
    end

    def update_link(link_id, changes)
      @routes.data('portal.updateLink', params: { 'linkId' => link_id }, body: changes)
    end

    def revoke_link(link_id, reason: nil)
      @routes.data('portal.revokeLink', params: { 'linkId' => link_id },
                                        body: RouteRequest.compact('reason' => RouteRequest.optional_text(reason, 'reason')))
    end

    def link_activity(link_id)
      @routes.data('portal.linkActivity', params: { 'linkId' => link_id })
    end

    # Emails a portal invite: { customerId, email?, allowedPlanIds?, ... }.
    def send_invite(invite)
      @routes.data('portal.sendInvite', body: invite)
    end

    # Portal settings (branding, allowed origins).
    def get_settings
      @routes.data('portal.getSettings')
    end

    def update_settings(settings)
      @routes.data('portal.updateSettings', body: settings)
    end
  end

  # subscriptions.products: catalog products (groups of plans).
  class SubscriptionProducts
    def initialize(routes)
      @routes = routes
    end

    def create(product)
      @routes.data('products.create', body: product)
    end

    # Filters: limit, cursor, active.
    def list(**filters)
      @routes.page('products.list', query: filters)
    end

    def iterate(**filters, &block)
      RouteRequest.each_item(filters, block) { |query| list(**query) }
    end

    def get(product_id)
      @routes.data('products.get', params: { 'productId' => product_id })
    end

    def update(product_id, changes)
      @routes.data('products.update', params: { 'productId' => product_id }, body: changes)
    end

    def archive(product_id)
      @routes.data('products.archive', params: { 'productId' => product_id })
    end

    def translations(product_id)
      @routes.data('products.translations', params: { 'productId' => product_id })
    end

    def upsert_translation(product_id, locale, translation)
      @routes.data('products.upsertTranslation', params: { 'productId' => product_id, 'locale' => locale }, body: translation)
    end
  end

  # subscriptions.features: entitlement features.
  class SubscriptionFeatures
    def initialize(routes)
      @routes = routes
    end

    def create(feature)
      @routes.data('features.create', body: feature)
    end

    # Any scalar filter is forwarded.
    def list(**filters)
      @routes.page('features.list', query: filters)
    end

    def get(feature_id)
      @routes.data('features.get', params: { 'featureId' => feature_id })
    end

    def update(feature_id, changes)
      @routes.data('features.update', params: { 'featureId' => feature_id }, body: changes)
    end

    def delete(feature_id)
      @routes.data('features.delete', params: { 'featureId' => feature_id })
    end

    def translations(feature_id)
      @routes.data('features.translations', params: { 'featureId' => feature_id })
    end

    def upsert_translation(feature_id, locale, translation)
      @routes.data('features.upsertTranslation', params: { 'featureId' => feature_id, 'locale' => locale }, body: translation)
    end
  end

  # subscriptions.addons.
  class SubscriptionAddons
    def initialize(routes)
      @routes = routes
    end

    def create(addon)
      @routes.data('addons.create', body: addon)
    end

    # Any scalar filter is forwarded.
    def list(**filters)
      @routes.page('addons.list', query: filters)
    end

    def update(addon_id, changes)
      @routes.data('addons.update', params: { 'addonId' => addon_id }, body: changes)
    end

    def deactivate(addon_id)
      @routes.data('addons.deactivate', params: { 'addonId' => addon_id })
    end
  end

  # subscriptions.usage: metered usage and entitlement checks.
  class SubscriptionUsage
    def initialize(routes)
      @routes = routes
    end

    # A metered-usage event: { customerId | subscriptionId, featureKey, quantity, timestamp?,
    # idempotencyKey?, ... }.
    def record(usage)
      @routes.data('usage.record', body: usage)
    end

    # Whether the customer is entitled / has quota left: { customerId | subscriptionId, featureKey,
    # requested?, ... }.
    def check_entitlement(check)
      @routes.data('usage.checkEntitlement', body: check)
    end
  end
end
