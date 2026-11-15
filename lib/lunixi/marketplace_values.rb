# frozen_string_literal: true

module Lunixi
  # Marketplace (sub-dealer split) values and routes: /api/v1/marketplace for dealers, commissions,
  # payouts and the audit log (access token only), and the split charges under
  # /api/v1/payments/marketplace (signed per request). The same codes as the Node and PHP SDKs.

  # Sub-dealer lifecycle. Only ACTIVE dealers can receive a split.
  module MarketplaceDealerStatus
    DRAFT = 'DRAFT'
    PENDING_KYC = 'PENDING_KYC'
    ACTIVE = 'ACTIVE'
    SUSPENDED = 'SUSPENDED'
    HOLD = 'HOLD'
    CLOSED = 'CLOSED'
    ALL = [DRAFT, PENDING_KYC, ACTIVE, SUSPENDED, HOLD, CLOSED].freeze
  end

  # dealerType of a sub-dealer.
  module MarketplaceDealerType
    LEGAL_ENTITY = 'LEGAL_ENTITY'
    INDIVIDUAL = 'INDIVIDUAL'
    ALL = [LEGAL_ENTITY, INDIVIDUAL].freeze
  end

  # multiSellerPolicy of a split charge: every seller leg must be eligible, or the eligible legs may go
  # through without the others.
  module MarketplaceMultiSellerPolicy
    ALL_OR_NOTHING = 'ALL_OR_NOTHING'
    PARTIAL_ALLOWED = 'PARTIAL_ALLOWED'
    ALL = [ALL_OR_NOTHING, PARTIAL_ALLOWED].freeze
  end

  # Hosted dealer onboarding wizard (Lunixi::Marketplace.onboarding_url when the answer carries no url).
  MARKETPLACE_DEALER_ONBOARDING_HOSTED_BASE = 'https://altbayi.lunixi.com'

  # Fields of a seller leg: the aggregate amount of one sub-dealer.
  MARKETPLACE_SELLER_FIELDS = %w[subDealerId amountMinor scenario].freeze

  # Fields a split card charge (charge_marketplace_card2d / 3d) needs besides the seller legs: the
  # commercial context of a traceable card payment.
  MARKETPLACE_CHARGE_REQUIRED_FIELDS = %w[amount currency orderId card buyer billingAddress basketItems].freeze

  marketplace_base = '/api/v1/marketplace'
  split_base = '/api/v1/payments/marketplace'
  route = lambda do |method, path, **extra|
    RouteRequest.route(method, path, step_up: false, idempotency_key: 'none', **extra)
  end
  charge = ->(path) { route.call('POST', path, step_up: true, idempotency_key: 'optional', free: true) }

  # Every marketplace route the SDK calls. The same table as the Node SDK's MARKETPLACE_ROUTES; the
  # parity test compares it with the shared catalog.
  MARKETPLACE_ROUTES = {
    'createCheckoutIntent' => charge.call("#{split_base}/intents"),
    'chargeMarketplaceCard2d' => charge.call("#{split_base}/2d"),
    'chargeMarketplaceCard3d' => charge.call("#{split_base}/3d"),

    'createDealer' => route.call('POST', "#{marketplace_base}/dealers", required: %w[legalName],
                                                                        optional: %w[taxId dealerType categoryCode email externalRef]),
    'bulkCreateDealers' => route.call('POST', "#{marketplace_base}/dealers/bulk", required: %w[dealers]),
    'listDealers' => route.call('GET', "#{marketplace_base}/dealers", query: %w[status search limit offset]),
    'getDealer' => route.call('GET', "#{marketplace_base}/dealers/:dealerId"),
    'updateDealerStatus' => route.call('PUT', "#{marketplace_base}/dealers/:dealerId/status", required: %w[status]),
    'onboardingToken' => route.call('POST', "#{marketplace_base}/dealers/:dealerId/onboarding-token"),
    'dealerApplication' => route.call('GET', "#{marketplace_base}/dealers/:dealerId/application"),
    'submitDealerApplication' => route.call('POST', "#{marketplace_base}/dealers/:dealerId/submit", free: true),
    'setDealerTerms' => route.call('POST', "#{marketplace_base}/dealers/:dealerId/terms", free: true),
    'signDealerContract' => route.call('POST', "#{marketplace_base}/dealers/:dealerId/sign", free: true),
    'activateDealer' => route.call('POST', "#{marketplace_base}/dealers/:dealerId/activate"),
    'recordDealerKycResult' => route.call('POST', "#{marketplace_base}/dealers/:dealerId/kyc-result", free: true),

    'payoutLedger' => route.call('GET', "#{marketplace_base}/payout-ledger", query: %w[status subDealerId days limit]),
    'transactions' => route.call('GET', "#{marketplace_base}/transactions", query: %w[status subDealerId limit]),
    'commissionRules' => route.call('GET', "#{marketplace_base}/commission-rules", query: %w[limit]),
    'upsertCommissionRule' => route.call('POST', "#{marketplace_base}/commission-rules", free: true),
    'previewCommissionRule' => route.call('POST', "#{marketplace_base}/commission-rules/preview", free: true),
    'resolveCommission' => route.call('GET', "#{marketplace_base}/commission/resolve", query: %w[subDealerId categoryCode mtdVolumeMinor]),

    'createPayout' => route.call('POST', "#{marketplace_base}/payouts", free: true),
    'markPayoutPaid' => route.call('POST', "#{marketplace_base}/payouts/:payoutId/mark-paid", free: true),
    'bulkMarkPayoutsPaid' => route.call('POST', "#{marketplace_base}/payouts/bulk-mark-paid", free: true),

    'auditLog' => route.call('GET', "#{marketplace_base}/audit-log", query: %w[limit type]),
    'verifyAuditLog' => route.call('GET', "#{marketplace_base}/audit-log/verify")
  }.freeze
end
