# frozen_string_literal: true

module Lunixi
  # Physical POS values, request fields and filters (/api/v1/physical-pos).
  #
  # Statuses and operations are open sets on the wire: the SDK lists the values the gateway sends today
  # and never rejects one it does not know. The field and filter lists are closed: the gateway rejects
  # an unknown body field or query parameter with 400, so the SDK checks them before sending.
  module PhysicalPosPaymentOperation
    SALE = 'SALE'
    PREAUTH_OPEN = 'PREAUTH_OPEN'
    REFUND_UNMATCHED = 'REFUND_UNMATCHED'
    VOID = 'VOID'
    REFUND = 'REFUND'
    PREAUTH_CLOSE = 'PREAUTH_CLOSE'
    PREAUTH_CANCEL = 'PREAUTH_CANCEL'

    # Operations that start a root payment (create_payment).
    ROOT = [SALE, PREAUTH_OPEN, REFUND_UNMATCHED].freeze
    # Operations of a reversal (create_reversal).
    REVERSAL = [VOID, REFUND, PREAUTH_CLOSE, PREAUTH_CANCEL].freeze
    ALL = (ROOT + REVERSAL).freeze
  end

  module PhysicalPosPaymentStatus
    NOT_STARTED = 'NOT_STARTED'
    IN_PROGRESS = 'IN_PROGRESS'
    APPROVED = 'APPROVED'
    PARTIALLY_APPROVED = 'PARTIALLY_APPROVED'
    DECLINED = 'DECLINED'
    CANCELLED = 'CANCELLED'
    EXPIRED = 'EXPIRED'
    FAILED = 'FAILED'
    UNKNOWN = 'UNKNOWN'
    MANUAL_REVIEW = 'MANUAL_REVIEW'

    ALL = [NOT_STARTED, IN_PROGRESS, APPROVED, PARTIALLY_APPROVED, DECLINED, CANCELLED, EXPIRED, FAILED, UNKNOWN, MANUAL_REVIEW].freeze
    FINAL_STATUSES = [APPROVED, PARTIALLY_APPROVED, DECLINED, CANCELLED, EXPIRED, FAILED].freeze
  end

  module PhysicalPosReversalStatus
    NONE = 'NONE'
    PARTIALLY_REFUNDED = 'PARTIALLY_REFUNDED'
    REFUNDED = 'REFUNDED'
    VOIDED = 'VOIDED'
    PREAUTH_CLOSED = 'PREAUTH_CLOSED'
    PREAUTH_CANCELLED = 'PREAUTH_CANCELLED'
    PREAUTH_EXPIRED = 'PREAUTH_EXPIRED'

    ALL = [NONE, PARTIALLY_REFUNDED, REFUNDED, VOIDED, PREAUTH_CLOSED, PREAUTH_CANCELLED, PREAUTH_EXPIRED].freeze
  end

  # Webhook event types. physical_pos.payment.created and .in_progress are internal and never delivered.
  # Reversals (void, refund, pre-authorisation close / cancel) use the same payment events; tell them
  # apart with data.operation and data.rootPaymentId, and the original payment's source with
  # data.original.origin.
  #
  # PAYMENT_DEVICE_SALE reports a sale made directly on the device (origin: DEVICE_DIRECT): it arrives
  # approved, with deviceOccurredAt; no approved event is sent for it. Its refund comes with the usual
  # payment events (data.original.origin: DEVICE_DIRECT).
  #
  # End-of-day events (physical_pos.settlement.*) have their own payloads: completed (the device's
  # result with its bank lines; any source), failed (a scheduled run could not finish in its window),
  # skipped (a scheduled run was skipped for a reason you can fix) and overdue (no result within the
  # policy's threshold). They carry no historySeq; deduplicate them by the event id.
  module PhysicalPosEvents
    PAYMENT_APPROVED = 'physical_pos.payment.approved'
    PAYMENT_PARTIALLY_APPROVED = 'physical_pos.payment.partially_approved'
    PAYMENT_DECLINED = 'physical_pos.payment.declined'
    PAYMENT_CANCELLED = 'physical_pos.payment.cancelled'
    PAYMENT_EXPIRED = 'physical_pos.payment.expired'
    PAYMENT_FAILED = 'physical_pos.payment.failed'
    PAYMENT_UNKNOWN = 'physical_pos.payment.unknown'
    PAYMENT_MANUAL_REVIEW = 'physical_pos.payment.manual_review'
    PAYMENT_DEVICE_SALE = 'physical_pos.payment.device_sale'
    FISCAL_DOCUMENT_ISSUED = 'physical_pos.fiscal_document.issued'
    FISCAL_DOCUMENT_FAILED = 'physical_pos.fiscal_document.failed'
    FISCAL_DOCUMENT_CANCELLED = 'physical_pos.fiscal_document.cancelled'
    FISCAL_DOCUMENT_ACTION_REQUIRED = 'physical_pos.fiscal_document.action_required'
    SETTLEMENT_COMPLETED = 'physical_pos.settlement.completed'
    SETTLEMENT_FAILED = 'physical_pos.settlement.failed'
    SETTLEMENT_OVERDUE = 'physical_pos.settlement.overdue'
    SETTLEMENT_SKIPPED = 'physical_pos.settlement.skipped'
    # Subscription pattern for every physical POS event.
    ALL_EVENTS = 'physical_pos.*'

    PAYMENT_EVENTS = [PAYMENT_APPROVED, PAYMENT_PARTIALLY_APPROVED, PAYMENT_DECLINED, PAYMENT_CANCELLED, PAYMENT_EXPIRED,
                      PAYMENT_FAILED, PAYMENT_UNKNOWN, PAYMENT_MANUAL_REVIEW, PAYMENT_DEVICE_SALE].freeze
    FISCAL_DOCUMENT_EVENTS = [FISCAL_DOCUMENT_ISSUED, FISCAL_DOCUMENT_FAILED, FISCAL_DOCUMENT_CANCELLED, FISCAL_DOCUMENT_ACTION_REQUIRED].freeze
    SETTLEMENT_EVENTS = [SETTLEMENT_COMPLETED, SETTLEMENT_FAILED, SETTLEMENT_OVERDUE, SETTLEMENT_SKIPPED].freeze
    ALL = (PAYMENT_EVENTS + FISCAL_DOCUMENT_EVENTS + SETTLEMENT_EVENTS).freeze
  end

  PHYSICAL_POS_EVENT_PATTERN = PhysicalPosEvents::ALL_EVENTS
  PHYSICAL_POS_EVENT_TYPES = PhysicalPosEvents::ALL

  # Idempotency-Key of a physical POS route: 8–200 printable ASCII characters, no space.
  PHYSICAL_POS_IDEMPOTENCY_KEY_PATTERN = /\A[\x21-\x7E]{8,200}\z/
  PHYSICAL_POS_MAX_LIMIT = 100
  PHYSICAL_POS_ROW_VERSION_MAX = 2_147_483_647

  # 5xx codes after which the gateway guarantees nothing was written (the payment did not start). Any
  # other 5xx, and a request without an HTTP answer, leaves the outcome of a payment write unknown.
  PHYSICAL_POS_NOT_STARTED_CODES = %w[
    physical_pos.presence.unavailable physical_pos.signing.unavailable physical_pos.service.busy
    physical_pos.service.clock_skew physical_pos.service.not_configured
  ].freeze

  PHYSICAL_POS_PAYMENT_TARGET_FIELDS = %w[deviceId vendorCode serialNumber externalRef].freeze
  PHYSICAL_POS_SALE_ITEM_FIELDS = %w[lineNo name quantityMilli unitCode unitPriceMinor taxGroupCode lineTotalMinor barcode].freeze
  PHYSICAL_POS_REFUND_ITEM_FIELDS = %w[lineNo quantityMilli amountMinor].freeze

  # Request bodies: { field => kind }. Kinds: string, int, money, bool, strings (array of strings),
  # rowVersion, target, saleItems, refundItems. A * suffix marks a required field; ? allows nil (an
  # explicit clear, sent as JSON null).
  PHYSICAL_POS_REQUEST_FIELDS = {
    'createPayment' => {
      'operation' => 'string*', 'target' => 'target*', 'amountMinor' => 'money*', 'currency' => 'string*',
      'installmentCount' => 'int?', 'instrument' => 'string?', 'merchantReference' => 'string?',
      'allowDuplicateReference' => 'bool', 'startTimeoutSeconds' => 'int?', 'terminalAcquirerId' => 'string?',
      'items' => 'saleItems', 'interaction' => 'string?', 'terminalProviderId' => 'string?'
    },
    'createReversal' => {
      'operation' => 'string*', 'amountMinor' => 'money', 'currency' => 'string*', 'merchantReference' => 'string?',
      'startTimeoutSeconds' => 'int?', 'target' => 'target?', 'items' => 'refundItems'
    },
    'createStore' => {
      'code' => 'string*', 'name' => 'string*', 'city' => 'string', 'district' => 'string', 'addressLine' => 'string',
      'timezone' => 'string', 'externalRef' => 'string'
    },
    'updateStore' => {
      'rowVersion' => 'rowVersion*', 'name' => 'string', 'city' => 'string?', 'district' => 'string?',
      'addressLine' => 'string?', 'timezone' => 'string', 'externalRef' => 'string?'
    },
    'statusChange' => { 'rowVersion' => 'rowVersion*', 'reasonCode' => 'string*' },
    'createRegister' => { 'code' => 'string*', 'name' => 'string*' },
    'updateRegister' => { 'rowVersion' => 'rowVersion*', 'name' => 'string' },
    'createTerminal' => {
      'code' => 'string*', 'displayName' => 'string*', 'vendorCode' => 'string', 'virtualSerial' => 'string',
      'vendorTerminalRef' => 'string'
    },
    'updateTerminal' => { 'rowVersion' => 'rowVersion*', 'displayName' => 'string', 'vendorCode' => 'string' },
    'addTerminalAcquirer' => {
      'vendorAcquirerRef' => 'string*', 'merchantNumber' => 'string*', 'terminalNumber' => 'string*', 'label' => 'string',
      'currencies' => 'strings*'
    },
    'updateTerminalAcquirer' => { 'rowVersion' => 'rowVersion*', 'label' => 'string?', 'currencies' => 'strings', 'status' => 'string' },
    'addTerminalProvider' => {
      'vendorAccountId' => 'string*', 'merchantCode' => 'string*', 'terminalCode' => 'string*', 'productCode' => 'string',
      'label' => 'string'
    },
    'updateTerminalProvider' => { 'rowVersion' => 'rowVersion*', 'label' => 'string?', 'status' => 'string' },
    'changeTerminalDevice' => { 'rowVersion' => 'rowVersion*', 'deviceId' => 'string*', 'reasonCode' => 'string*' },
    'createDevice' => {
      'vendorCode' => 'string*', 'deviceModelId' => 'string*', 'serialNumber' => 'string*', 'displayName' => 'string',
      'externalRef' => 'string', 'storeId' => 'string', 'registerId' => 'string', 'integrationChannel' => 'string*',
      'channelVariant' => 'string', 'appMode' => 'string'
    },
    'updateDevice' => {
      'rowVersion' => 'rowVersion*', 'displayName' => 'string?', 'externalRef' => 'string?', 'integrationChannel' => 'string',
      'channelVariant' => 'string?', 'appMode' => 'string?'
    },
    'assignDevice' => { 'rowVersion' => 'rowVersion*', 'storeId' => 'string*', 'registerId' => 'string?', 'reasonCode' => 'string*' },
    'changeDeviceLifecycle' => { 'rowVersion' => 'rowVersion*', 'target' => 'string*', 'reasonCode' => 'string*' },
    'revokeDeviceKey' => { 'rowVersion' => 'rowVersion*', 'reasonCode' => 'string*' },
    'revertDeviceEnrollment' => { 'reasonCode' => 'string*' },
    'revokeActivationCode' => { 'reasonCode' => 'string*' },
    'setSettlementPolicy' => {
      'mode' => 'string*', 'scheduleTime' => 'string', 'timeZone' => 'string', 'scheduleDays' => 'strings',
      'retryWindowMinutes' => 'int', 'retryIntervalMinutes' => 'int', 'offlineBehavior' => 'string',
      'overdueAlertHours' => 'int', 'expectedRowVersion' => 'rowVersion'
    }
  }.transform_values(&:freeze).freeze

  physical_pos_page = %w[limit cursor].freeze
  physical_pos_entity_page = (physical_pos_page + ['includeTotal']).freeze
  physical_pos_report = %w[dateFrom dateTo deviceId storeId].freeze

  # Query parameters per route; anything else is rejected before sending. history covers the audit,
  # link, assignment and key lists.
  PHYSICAL_POS_FILTERS = {
    'listPayments' => physical_pos_page + %w[deviceId paymentStatus createdFrom createdTo merchantReference],
    'listTransactions' => physical_pos_page + %w[deviceId storeId registerId paymentStatus createdFrom createdTo merchantReference
                                                 amountFromMinor amountToMinor origin operation],
    'listAmbiguousPayments' => physical_pos_page + %w[deviceId paymentStatus],
    'getSalesSummary' => physical_pos_report + ['groupBy'],
    'getTaxSummary' => physical_pos_report,
    'listSettlements' => physical_pos_page + %w[deviceId lineStatus createdFrom createdTo],
    'listSettlementRuns' => physical_pos_entity_page + %w[deviceId source runStatus createdFrom createdTo],
    'listDeviceModels' => %w[vendorCode deviceType status],
    'listStores' => physical_pos_entity_page + %w[status q],
    'listRegisters' => physical_pos_entity_page + ['status'],
    'listTerminals' => physical_pos_entity_page + %w[status q],
    'listTerminalAcquirers' => physical_pos_entity_page,
    'listTerminalProviders' => physical_pos_entity_page,
    'listDevices' => physical_pos_entity_page + %w[storeId registerId vendorCode deviceModelId deviceType lifecycleStatus
                                                   ownershipStatus integrationChannel q],
    'history' => physical_pos_page
  }.transform_values { |names| names.dup.freeze }.freeze

  # Filters scanned for card numbers before sending.
  PHYSICAL_POS_FREE_TEXT_FILTERS = %w[merchantReference q].freeze
end
