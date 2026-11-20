# frozen_string_literal: true

module Lunixi
  # Subscription values and routes (/api/v1/subscriptions, and the portal-link routes under
  # /api/panel/v1/subscriptions/portal). The same codes as the Node and PHP SDKs.

  # Subscription status.
  module SubscriptionStatus
    # startsAt is in the future.
    PENDING = 'PENDING'
    TRIALING = 'TRIALING'
    ACTIVE = 'ACTIVE'
    # A charge failed; dunning runs.
    PAST_DUE = 'PAST_DUE'
    # Dunning exhausted; grace period.
    UNPAID = 'UNPAID'
    # Paused by the merchant; no charges.
    PAUSED = 'PAUSED'
    UPGRADED = 'UPGRADED'
    DOWNGRADED = 'DOWNGRADED'
    CANCELED = 'CANCELED'
    # The recurrence ran out.
    EXPIRED = 'EXPIRED'
    ALL = [PENDING, TRIALING, ACTIVE, PAST_DUE, UNPAID, PAUSED, UPGRADED, DOWNGRADED, CANCELED, EXPIRED].freeze
    # Live states: the subscription may be billed.
    ACTIVE_STATES = [TRIALING, ACTIVE, PAST_DUE].freeze
    # Terminal states: no further transition.
    TERMINAL_STATES = [UPGRADED, DOWNGRADED, CANCELED, EXPIRED].freeze
  end

  SUBSCRIPTION_ACTIVE_STATES = SubscriptionStatus::ACTIVE_STATES
  SUBSCRIPTION_TERMINAL_STATES = SubscriptionStatus::TERMINAL_STATES

  # Invoice status: DRAFT -> OPEN -> PAID | UNCOLLECTIBLE | VOID.
  module SubscriptionInvoiceStatus
    DRAFT = 'DRAFT'
    OPEN = 'OPEN'
    PAID = 'PAID'
    UNCOLLECTIBLE = 'UNCOLLECTIBLE'
    VOID = 'VOID'
    ALL = [DRAFT, OPEN, PAID, UNCOLLECTIBLE, VOID].freeze
  end

  # Errors of customers.upsert: a missing or invalid customer field (details.field).
  module SubscriptionCustomerErrorCode
    FIELD_REQUIRED = 'subscription.customer.field_required'
    FIELD_INVALID = 'subscription.customer.field_invalid'
    ALL = [FIELD_REQUIRED, FIELD_INVALID].freeze
  end

  # How invoices are collected (collectionMethod): the saved card is charged each cycle (AUTO_CHARGE,
  # the default), the invoice is finalised but not charged (SEND_INVOICE), or collection is up to you
  # (MANUAL).
  module SubscriptionCollectionMethod
    AUTO_CHARGE = 'AUTO_CHARGE'
    SEND_INVOICE = 'SEND_INVOICE'
    MANUAL = 'MANUAL'
    ALL = [AUTO_CHARGE, SEND_INVOICE, MANUAL].freeze
  end

  # billing.frequency of a plan.
  module SubscriptionBillingFrequency
    DAILY = 'DAILY'
    WEEKLY = 'WEEKLY'
    MONTHLY = 'MONTHLY'
    YEARLY = 'YEARLY'
    ALL = [DAILY, WEEKLY, MONTHLY, YEARLY].freeze
  end

  # verificationMode of a saved card.
  module SubscriptionCardVerificationMode
    NONE = 'NONE'
    ON_ADD = 'ON_ADD'
    FIRST_CHARGE = 'FIRST_CHARGE'
    ALL = [NONE, ON_ADD, FIRST_CHARGE].freeze
  end

  # behavior of a plan change: now (prorated) or at the next period.
  module SubscriptionPlanChangeBehavior
    IMMEDIATE = 'IMMEDIATE'
    NEXT_PERIOD = 'NEXT_PERIOD'
    ALL = [IMMEDIATE, NEXT_PERIOD].freeze
  end

  # sdkMode of a portal SDK session.
  module SubscriptionPortalSdkMode
    FULL = 'FULL'
    HEADLESS = 'HEADLESS'
    HYBRID = 'HYBRID'
    ALL = [FULL, HEADLESS, HYBRID].freeze
  end

  # Webhook event types (the same signed envelope as payment events; data amounts are minor-unit
  # strings).
  module SubscriptionEvents
    CREATED = 'subscription.created'
    ACTIVATED = 'subscription.activated'
    TRIAL_WILL_END = 'subscription.trial_will_end'
    PAUSED = 'subscription.paused'
    RESUMED = 'subscription.resumed'
    CANCEL_SCHEDULED = 'subscription.cancel_scheduled'
    CANCELED = 'subscription.canceled'
    UPGRADED = 'subscription.upgraded'
    DOWNGRADED = 'subscription.downgraded'
    PLAN_CHANGE_SCHEDULED = 'subscription.plan_change_scheduled'
    PENDING_CHANGE_APPLIED = 'subscription.pending_change_applied'
    PAYMENT_CARD_SWAPPED = 'subscription.payment_card_swapped'
    PAYMENT_METHOD_LOST = 'subscription.payment_method_lost'
    INVOICE_CREATED = 'invoice.created'
    INVOICE_PAID = 'invoice.paid'
    INVOICE_PAYMENT_FAILED = 'invoice.payment_failed'
    INVOICE_VOIDED = 'invoice.voided'
    CARD_ADDED = 'card.added'
    CARD_SET_DEFAULT = 'card.set_default'
    CARD_UPDATED = 'card.updated'
    CARD_DEACTIVATED = 'card.deactivated'
    CARD_EXPIRING_SOON = 'card.expiring_soon'
    CARD_EXPIRED = 'card.expired'
    ALL = [CREATED, ACTIVATED, TRIAL_WILL_END, PAUSED, RESUMED, CANCEL_SCHEDULED, CANCELED, UPGRADED, DOWNGRADED, PLAN_CHANGE_SCHEDULED,
           PENDING_CHANGE_APPLIED, PAYMENT_CARD_SWAPPED, PAYMENT_METHOD_LOST, INVOICE_CREATED, INVOICE_PAID, INVOICE_PAYMENT_FAILED,
           INVOICE_VOIDED, CARD_ADDED, CARD_SET_DEFAULT, CARD_UPDATED, CARD_DEACTIVATED, CARD_EXPIRING_SOON, CARD_EXPIRED].freeze
  end

  SUBSCRIPTION_EVENT_TYPES = SubscriptionEvents::ALL

  # Hosted customer portal; a portal link's token opens it (Lunixi::Subscriptions.portal_url).
  SUBSCRIPTION_PORTAL_HOSTED_BASE = 'https://portal.lunixi.com'

  # Fields of a plan's billing rule.
  SUBSCRIPTION_BILLING_RULE_FIELDS = %w[frequency interval byMonthDay byWeekDay timezone lastDayOfMonthFix count].freeze

  subscriptions_base = '/api/v1/subscriptions'
  portal_panel = '/api/panel/v1/subscriptions/portal'
  cursor_query = %w[pageSize pageToken].freeze
  route = lambda do |method, path, **extra|
    RouteRequest.route(method, path, step_up: false, idempotency_key: 'none', **extra)
  end

  # Every subscription route the SDK calls: method, path, whether it is signed (never: the subscription
  # surface takes the access token only), the Idempotency-Key rule and the body / query fields. Keys are
  # the operation names ("plans.create"). The same table as the Node SDK's SUBSCRIPTION_ROUTES; the
  # parity test compares it with the shared catalog.
  SUBSCRIPTION_ROUTES = {
    'create' => route.call('POST', "#{subscriptions_base}/subscriptions",
                           idempotency_key: 'required', required: %w[customerId planId idempotencyKey],
                           optional: %w[paymentCardId paymentMethodId collectionMethod priceUpdatePolicy entitlementPolicy billingTimezone startsAt
                                        chargeOnCreate billingCycleAnchorOverride skipTrial metadata]),
    'get' => route.call('GET', "#{subscriptions_base}/subscriptions/:subscriptionId"),
    'list' => route.call('GET', "#{subscriptions_base}/subscriptions", query: %w[customerId status] + cursor_query),
    'cancel' => route.call('POST', "#{subscriptions_base}/subscriptions/:subscriptionId/cancel", required: %w[cancelAtPeriodEnd], optional: %w[reason]),
    'pause' => route.call('POST', "#{subscriptions_base}/subscriptions/:subscriptionId/pause", optional: %w[resumeAt], optional_body: true),
    'resume' => route.call('POST', "#{subscriptions_base}/subscriptions/:subscriptionId/resume"),
    'changePlan' => route.call('POST', "#{subscriptions_base}/subscriptions/:subscriptionId/change-plan",
                               idempotency_key: 'optional', required: %w[newPlanId], optional: %w[behavior reason idempotencyKey]),
    'auditLogs' => route.call('GET', "#{subscriptions_base}/subscriptions/:subscriptionId/audit-logs", query: %w[limit pageToken]),

    'plans.create' => route.call('POST', "#{subscriptions_base}/plans",
                                 idempotency_key: 'optional', required: %w[productId code name price currency billing],
                                 optional: %w[description trialPeriodDays maxDunningAttempts dunningScheduleDays gracePeriodDays metadata]),
    'plans.get' => route.call('GET', "#{subscriptions_base}/plans/:planId"),
    'plans.list' => route.call('GET', "#{subscriptions_base}/plans", query: %w[productId includeArchived] + cursor_query),
    'plans.update' => route.call('PATCH', "#{subscriptions_base}/plans/:planId", free: true),
    'plans.archive' => route.call('DELETE', "#{subscriptions_base}/plans/:planId"),
    'plans.translations' => route.call('GET', "#{subscriptions_base}/plans/:planId/translations"),
    'plans.upsertTranslation' => route.call('PATCH', "#{subscriptions_base}/plans/:planId/translations/:locale", free: true),

    # Renewals take the buyer from this record: identity and billing details are required (400
    # subscription.customer.field_required).
    'customers.upsert' => route.call('PUT', "#{subscriptions_base}/customers",
                                     idempotency_key: 'optional',
                                     required: %w[externalId name surname email gsmNumber identityNumber billingAddress billingCity billingCountry
                                                  billingZipCode],
                                     optional: %w[billingContactName shippingContactName shippingAddress shippingCity shippingCountry
                                                  shippingZipCode]),
    'customers.get' => route.call('GET', "#{subscriptions_base}/customers/:customerId"),
    'customers.getByExternalId' => route.call('GET', "#{subscriptions_base}/customers/by-external/:externalId"),
    'customers.list' => route.call('GET', "#{subscriptions_base}/customers", query: %w[search includeArchived] + cursor_query),
    'customers.creditBalance' => route.call('GET', "#{subscriptions_base}/customers/:customerId/credit-balance"),
    'customers.adjustCredit' => route.call('POST', "#{subscriptions_base}/customers/:customerId/credit-balance/adjust", free: true),
    'customers.archive' => route.call('DELETE', "#{subscriptions_base}/customers/:customerId"),

    'cards.add' => route.call('POST', "#{subscriptions_base}/cards",
                              idempotency_key: 'optional', required: %w[customerId paymentMethodToken],
                              optional: %w[brand last4 bin expireMonth expireYear cardholderName isDefault nickname verificationMode supportedCurrencies]),
    'cards.get' => route.call('GET', "#{subscriptions_base}/cards/:cardId"),
    'cards.list' => route.call('GET', "#{subscriptions_base}/cards", query: %w[customerId includeInactive] + cursor_query),
    'cards.setDefault' => route.call('POST', "#{subscriptions_base}/cards/:cardId/set-default"),
    'cards.deactivate' => route.call('DELETE', "#{subscriptions_base}/cards/:cardId", optional: %w[reason], optional_body: true),
    'cards.verify' => route.call('POST', "#{subscriptions_base}/cards/:cardId/verify", free: true, optional_body: true),
    'cards.update' => route.call('PATCH', "#{subscriptions_base}/cards/:cardId", free: true),

    'invoices.list' => route.call('GET', "#{subscriptions_base}/invoices", query: %w[subscriptionId status] + cursor_query),
    'invoices.get' => route.call('GET', "#{subscriptions_base}/invoices/:invoiceId"),
    'invoices.void' => route.call('POST', "#{subscriptions_base}/invoices/:invoiceId/void", optional: %w[reason], optional_body: true),
    'invoices.retryCharge' => route.call('POST', "#{subscriptions_base}/invoices/:invoiceId/retry-charge", idempotency_key: 'optional'),

    'portal.createSdkSession' => route.call('POST', "#{subscriptions_base}/portal/sdk-session",
                                            required: %w[customerId origin], optional: %w[sdkMode portalLinkId]),
    'portal.createPortalLink' => route.call('POST', "#{portal_panel}/links", free: true),
    'portal.listLinks' => route.call('GET', "#{portal_panel}/links", query: %w[customerId status limit]),
    'portal.getLink' => route.call('GET', "#{portal_panel}/links/:linkId"),
    'portal.updateLink' => route.call('PATCH', "#{portal_panel}/links/:linkId", free: true),
    'portal.revokeLink' => route.call('DELETE', "#{portal_panel}/links/:linkId", optional: %w[reason], optional_body: true),
    'portal.linkActivity' => route.call('GET', "#{portal_panel}/links/:linkId/activity"),
    'portal.sendInvite' => route.call('POST', "#{portal_panel}/invite", free: true),
    'portal.getSettings' => route.call('GET', "#{portal_panel}/settings"),
    'portal.updateSettings' => route.call('PUT', "#{portal_panel}/settings", free: true),

    'products.create' => route.call('POST', "#{subscriptions_base}/products", free: true),
    'products.list' => route.call('GET', "#{subscriptions_base}/products", query: %w[limit cursor active]),
    'products.get' => route.call('GET', "#{subscriptions_base}/products/:productId"),
    'products.update' => route.call('PATCH', "#{subscriptions_base}/products/:productId", free: true),
    'products.archive' => route.call('DELETE', "#{subscriptions_base}/products/:productId"),
    'products.translations' => route.call('GET', "#{subscriptions_base}/products/:productId/translations"),
    'products.upsertTranslation' => route.call('PATCH', "#{subscriptions_base}/products/:productId/translations/:locale", free: true),

    'features.create' => route.call('POST', "#{subscriptions_base}/features", free: true),
    'features.list' => route.call('GET', "#{subscriptions_base}/features", any_query: true),
    'features.get' => route.call('GET', "#{subscriptions_base}/features/:featureId"),
    'features.update' => route.call('PATCH', "#{subscriptions_base}/features/:featureId", free: true),
    'features.delete' => route.call('DELETE', "#{subscriptions_base}/features/:featureId"),
    'features.translations' => route.call('GET', "#{subscriptions_base}/features/:featureId/translations"),
    'features.upsertTranslation' => route.call('PATCH', "#{subscriptions_base}/features/:featureId/translations/:locale", free: true),

    'addons.create' => route.call('POST', "#{subscriptions_base}/addons", free: true),
    'addons.list' => route.call('GET', "#{subscriptions_base}/addons", any_query: true),
    'addons.update' => route.call('PATCH', "#{subscriptions_base}/addons/:addonId", free: true),
    'addons.deactivate' => route.call('DELETE', "#{subscriptions_base}/addons/:addonId"),

    'usage.record' => route.call('POST', "#{subscriptions_base}/usage/record", free: true),
    'usage.checkEntitlement' => route.call('POST', "#{subscriptions_base}/usage/check-entitlement", free: true)
  }.freeze
end
