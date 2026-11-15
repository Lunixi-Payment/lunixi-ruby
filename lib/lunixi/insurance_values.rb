# frozen_string_literal: true

module Lunixi
  # Insurance values, request fields and filters (/api/v1/insurance, product INSURANCE_SERVICE).

  # Who collects the premium. PROVIDER orders cannot be completed through this API yet.
  module InsurancePremiumCollectedBy
    MERCHANT = 'MERCHANT'
    PROVIDER = 'PROVIDER'
    ALL = [MERCHANT, PROVIDER].freeze
  end

  # Status of a quote option. Only a QUOTED option that has not expired becomes an order.
  module InsuranceQuoteStatus
    REQUESTED = 'REQUESTED'
    QUOTED = 'QUOTED'
    EXPIRED = 'EXPIRED'
    REJECTED = 'REJECTED'
    ERROR = 'ERROR'
    ALL = [REQUESTED, QUOTED, EXPIRED, REJECTED, ERROR].freeze
  end

  # The order's overall status, derived on every read from the four axes in this order: REFUNDED,
  # CANCELLED, FAILED, ACTION_REQUIRED, PROCESSING, PARTIALLY_ACTIVE, ACTIVE, CREATED.
  module InsuranceOrderStatus
    CREATED = 'CREATED'
    PROCESSING = 'PROCESSING'
    ACTION_REQUIRED = 'ACTION_REQUIRED'
    PARTIALLY_ACTIVE = 'PARTIALLY_ACTIVE'
    ACTIVE = 'ACTIVE'
    FAILED = 'FAILED'
    CANCELLED = 'CANCELLED'
    REFUNDED = 'REFUNDED'
    ALL = [CREATED, PROCESSING, ACTION_REQUIRED, PARTIALLY_ACTIVE, ACTIVE, FAILED, CANCELLED, REFUNDED].freeze
  end

  module InsuranceCollectionStatus
    NOT_STARTED = 'NOT_STARTED'
    PENDING = 'PENDING'
    ACTION_REQUIRED = 'ACTION_REQUIRED'
    COLLECTED = 'COLLECTED'
    FAILED = 'FAILED'
    UNKNOWN = 'UNKNOWN'
    ALL = [NOT_STARTED, PENDING, ACTION_REQUIRED, COLLECTED, FAILED, UNKNOWN].freeze
  end

  module InsurancePolicyStatus
    NOT_REQUESTED = 'NOT_REQUESTED'
    PENDING = 'PENDING'
    PARTIALLY_ISSUED = 'PARTIALLY_ISSUED'
    ISSUED = 'ISSUED'
    FAILED_RETRYABLE = 'FAILED_RETRYABLE'
    FAILED_FINAL = 'FAILED_FINAL'
    UNKNOWN = 'UNKNOWN'
    CANCEL_PENDING = 'CANCEL_PENDING'
    CANCELLED = 'CANCELLED'
    ALL = [NOT_REQUESTED, PENDING, PARTIALLY_ISSUED, ISSUED, FAILED_RETRYABLE, FAILED_FINAL, UNKNOWN, CANCEL_PENDING, CANCELLED].freeze
  end

  module InsuranceRefundStatus
    NONE = 'NONE'
    REQUIRED = 'REQUIRED'
    PENDING = 'PENDING'
    REFUNDED = 'REFUNDED'
    FAILED = 'FAILED'
    ALL = [NONE, REQUIRED, PENDING, REFUNDED, FAILED].freeze
  end

  # The policy document axis; it does not change the overall status.
  module InsuranceDocumentStatus
    NOT_AVAILABLE = 'NOT_AVAILABLE'
    PENDING = 'PENDING'
    AVAILABLE = 'AVAILABLE'
    FAILED = 'FAILED'
    ALL = [NOT_AVAILABLE, PENDING, AVAILABLE, FAILED].freeze
  end

  module InsurancePaymentMode
    LUNIXI_PAYMENT = 'LUNIXI_PAYMENT'
    EXTERNAL_PAYMENT = 'EXTERNAL_PAYMENT'
    NO_PAYMENT = 'NO_PAYMENT'
    ALL = [LUNIXI_PAYMENT, EXTERNAL_PAYMENT, NO_PAYMENT].freeze
  end

  module InsuranceOrderSurface
    MERCHANT_API = 'MERCHANT_API'
    CHECKOUT_FORM = 'CHECKOUT_FORM'
    PANEL = 'PANEL'
    ALL = [MERCHANT_API, CHECKOUT_FORM, PANEL].freeze
  end

  # Status of a lead. PENDING: the provider call is running. SUBMITTED: the provider received it
  # (insurance.lead.submitted). UNKNOWN: the outcome is not known; it is never sent again (open a new
  # lead with a new Idempotency-Key if needed). FAILED: refused or never reached the provider (errorCode).
  module InsuranceLeadStatus
    PENDING = 'PENDING'
    SUBMITTED = 'SUBMITTED'
    UNKNOWN = 'UNKNOWN'
    FAILED = 'FAILED'
    ALL = [PENDING, SUBMITTED, UNKNOWN, FAILED].freeze
  end

  # Reference code lists (insurance.list_reference_values(kind)). DISTRICT, DEVICE_MODEL, VEHICLE_MODEL,
  # BANK_BRANCH and PET_BREED need parentCode (province, brand, bank, CAT | DOG).
  module InsuranceReferenceKind
    COUNTRY = 'COUNTRY'
    CITY = 'CITY'
    DISTRICT = 'DISTRICT'
    DEVICE_BRAND = 'DEVICE_BRAND'
    DEVICE_MODEL = 'DEVICE_MODEL'
    VEHICLE_BRAND = 'VEHICLE_BRAND'
    VEHICLE_MODEL = 'VEHICLE_MODEL'
    VEHICLE_TYPE = 'VEHICLE_TYPE'
    PRODUCT_CATEGORY = 'PRODUCT_CATEGORY'
    VEHICLE_USAGE = 'VEHICLE_USAGE'
    LIABILITY_LIMIT = 'LIABILITY_LIMIT'
    OCCUPATION = 'OCCUPATION'
    PET_BREED = 'PET_BREED'
    DWELLING_TYPE = 'DWELLING_TYPE'
    DWELLING_FLOOR = 'DWELLING_FLOOR'
    BANK = 'BANK'
    BANK_BRANCH = 'BANK_BRANCH'
    FINANCE_INSTITUTION = 'FINANCE_INSTITUTION'
    MEDICAL_PROCEDURE_COVER = 'MEDICAL_PROCEDURE_COVER'
    ALL = [COUNTRY, CITY, DISTRICT, DEVICE_BRAND, DEVICE_MODEL, VEHICLE_BRAND, VEHICLE_MODEL, VEHICLE_TYPE, PRODUCT_CATEGORY,
           VEHICLE_USAGE, LIABILITY_LIMIT, OCCUPATION, PET_BREED, DWELLING_TYPE, DWELLING_FLOOR, BANK, BANK_BRANCH,
           FINANCE_INSTITUTION, MEDICAL_PROCEDURE_COVER].freeze
  end

  # Insurance webhook events (subscription insurance.*). Read them with Lunixi::InsuranceWebhook.parse;
  # deduplicate on the event id (data.eventId is the same value).
  module InsuranceEvents
    # The order's policies were issued.
    POLICY_ISSUED = 'insurance.policy.issued'
    # The policy could not be issued or the premium was not collected; data.errorCode says why.
    POLICY_FAILED = 'insurance.policy.failed'
    # The collected premium has to be refunded; data.errorCode says why.
    REFUND_REQUIRED = 'insurance.refund.required'
    # A policy document can be downloaded (policies[].documentUrl).
    POLICY_DOCUMENT_READY = 'insurance.policy.document_ready'
    # The provider confirmed the cancellation.
    POLICY_CANCELLED = 'insurance.policy.cancelled'
    # The premium refund completed.
    REFUND_COMPLETED = 'insurance.refund.completed'
    # The insurance provider received a lead; data is a lead summary, not an order.
    LEAD_SUBMITTED = 'insurance.lead.submitted'
    PATTERN = 'insurance.*'
    ORDER_EVENTS = [POLICY_ISSUED, POLICY_FAILED, REFUND_REQUIRED, POLICY_DOCUMENT_READY, POLICY_CANCELLED, REFUND_COMPLETED].freeze
    LEAD_EVENTS = [LEAD_SUBMITTED].freeze
    ALL = (ORDER_EVENTS + LEAD_EVENTS).freeze
  end

  # The type objects of the gateway's type body, one per insurance type (a product's typeObject).
  INSURANCE_TYPE_OBJECT_FIELDS = %w[tickets stay device product vehicle trip rental instrument event accident procedure pet residence abroadStay].freeze
  # Top-level fields of create_quote. The type objects are sent as given: their field rules are the
  # gateway's (422 insurance.validation.invalid with every details.errors[{ field, reason }]).
  INSURANCE_QUOTE_FIELDS = (%w[insuranceType schemaVersion currency paymentIntentId context merchantOrderId policyholder insured] +
                            INSURANCE_TYPE_OBJECT_FIELDS).freeze
  # Top-level fields of create_lead: the type body without basket, currency and order fields, plus
  # shipment, company and the free note.
  INSURANCE_LEAD_FIELDS = (%w[insuranceType schemaVersion policyholder insured] + INSURANCE_TYPE_OBJECT_FIELDS + %w[shipment company note]).freeze
  INSURANCE_PRODUCT_SEARCH_FIELDS = %w[currency insuranceType context].freeze
  INSURANCE_ORDER_FIELDS = %w[quoteId merchantOrderId consent].freeze
  INSURANCE_CONSENT_FIELDS = %w[termsVersion termsSha256 acceptedAt].freeze
  # Fields of confirm_payment (a premium collected outside Lunixi).
  INSURANCE_EXTERNAL_PAYMENT_FIELDS = %w[externalPaymentId paidAmount paidCurrency paidAt paymentProvider].freeze
  # Fields of externalRefund (refund_premium for a premium collected outside Lunixi).
  INSURANCE_EXTERNAL_REFUND_FIELDS = %w[externalRefundId refundedAt].freeze

  # Query filters each read accepts (the gateway rejects any other with 400).
  INSURANCE_FILTERS = {
    'listProducts' => %w[currency paymentIntentId insuranceType].freeze,
    'listReferenceValues' => %w[parentCode limit cursor].freeze,
    'listOrders' => %w[limit cursor paymentIntentId merchantOrderId].freeze,
    'getReconciliationSummary' => %w[from to connectionId insuranceType currency].freeze,
    'listReconciliationOrders' => %w[from to connectionId insuranceType currency limit cursor].freeze,
    'exportReconciliation' => %w[from to connectionId insuranceType currency cursor].freeze,
    'listLeads' => %w[limit cursor insuranceType status].freeze
  }.freeze

  # Idempotency-Key of the insurance routes: 8–200 printable ASCII characters. Required for create_order,
  # confirm_payment, issue_policy, cancel_order, refund_premium and create_lead; optional for
  # create_quote and bind_payment.
  INSURANCE_IDEMPOTENCY_KEY_PATTERN = RouteRequest::PRINTABLE_IDEMPOTENCY_KEY
  INSURANCE_MAX_LIMIT = 100
  # Most basket items one context.items may carry.
  INSURANCE_MAX_CONTEXT_ITEMS = 100
  # Orders in one reconciliation CSV file; a longer export ends with a continuation line.
  INSURANCE_EXPORT_ORDER_CAP = 20_000
  INSURANCE_LEAD_NOTE_MAX_LENGTH = 1000

  # data fields of the order webhooks (InsuranceEvents::ORDER_EVENTS); errorCode only on
  # insurance.policy.failed and insurance.refund.required.
  INSURANCE_WEBHOOK_FIELDS = %w[
    eventId eventType merchantId insuranceOrderId paymentIntentId merchantOrderId insuranceType premiumCollectedBy provider status
    collectionStatus policyStatus refundStatus documentStatus premiumAmount currency policies errorCode createdAt
  ].freeze
  # data fields of insurance.lead.submitted (lead: { leadId, insuranceType, schemaVersion, status, submittedAt, createdAt }).
  INSURANCE_LEAD_WEBHOOK_FIELDS = %w[eventId eventType merchantId lead createdAt].freeze
end
