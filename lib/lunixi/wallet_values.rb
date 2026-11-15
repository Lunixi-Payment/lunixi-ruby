# frozen_string_literal: true

module Lunixi
  # Wallet values and routes (/api/v1/wallet, product WALLET_SERVICE).
  module WalletAccountType
    PERSONAL = 'PERSONAL'
    BUSINESS = 'BUSINESS'
    ALL = [PERSONAL, BUSINESS].freeze
  end

  module WalletEndUserStatus
    ACTIVE = 'ACTIVE'
    FROZEN = 'FROZEN'
    CLOSED = 'CLOSED'
    ALL = [ACTIVE, FROZEN, CLOSED].freeze
  end

  module WalletKycLevel
    NONE = 'NONE'
    LOW = 'LOW'
    SUBSTANTIAL = 'SUBSTANTIAL'
    HIGH = 'HIGH'
    ALL = [NONE, LOW, SUBSTANTIAL, HIGH].freeze
  end

  module WalletOtpChannel
    EMAIL = 'EMAIL'
    SMS = 'SMS'
    PUSH = 'PUSH'
    ALL = [EMAIL, SMS, PUSH].freeze
  end

  module WalletQrType
    P2P_STATIC = 'P2P_STATIC'
    P2P_DYNAMIC = 'P2P_DYNAMIC'
    MERCHANT_STATIC = 'MERCHANT_STATIC'
    MERCHANT_DYNAMIC = 'MERCHANT_DYNAMIC'
    ALL = [P2P_STATIC, P2P_DYNAMIC, MERCHANT_STATIC, MERCHANT_DYNAMIC].freeze
  end

  module WalletQrImageFormat
    SVG = 'svg'
    PNG = 'png'
    ALL = [SVG, PNG].freeze
  end

  module WalletBulkTargetType
    WALLET = 'WALLET'
    IBAN = 'IBAN'
    ALL = [WALLET, IBAN].freeze
  end

  module WalletCorporateAccountStatus
    ACTIVE = 'ACTIVE'
    ARCHIVED = 'ARCHIVED'
    ALL = [ACTIVE, ARCHIVED].freeze
  end

  # Minor units as a decimal string: "12550" is 125.50 TRY. Never a number.
  WALLET_AMOUNT_PATTERN = /\A\d{1,18}\z/
  # The gateway trims the Idempotency-Key header and accepts 1–128 characters.
  WALLET_IDEMPOTENCY_KEY_MAX = 128
  # Body fields that carry a minor-unit amount string.
  WALLET_AMOUNT_FIELDS = %w[amount].freeze
  # Fields of the nested rows / items the gateway validates element by element ("route.field").
  WALLET_NESTED_FIELDS = {
    'importCorporateEmployees.rows' => { 'required' => %w[phone].freeze, 'optional' => %w[displayName externalCustomerId kycRef].freeze }.freeze,
    'offboardCorporateEmployees.rows' => { 'required' => [].freeze, 'optional' => %w[endUserId externalCustomerId].freeze }.freeze,
    'createBulkPayout.items' => { 'required' => %w[targetType targetRef amount].freeze, 'optional' => %w[beneficiaryName].freeze }.freeze
  }.freeze

  wallet_page = %w[limit cursor].freeze
  money_move = %w[endUserId sourceWalletAccountId amount currency].freeze
  iban_move = %w[endUserId sourceWalletAccountId beneficiaryName iban amount currency].freeze
  initiate_extra = %w[scheduleVersionId otpDestination otpChannel locale].freeze
  complete_required = %w[endUserId operationId integrityHash nonce].freeze
  complete_optional = %w[otpCode trustedActionToken].freeze

  # Every wallet route the SDK calls: method, path template, whether the gateway requires an
  # Idempotency-Key, the body fields it accepts (required / optional; forbidNonWhitelisted, so any other
  # field is a 400) and the query parameters. The same table as the Node SDK's WALLET_ROUTES; the parity
  # test compares it with the shared catalog field by field.
  WALLET_ROUTES = {
    'ping' => RouteRequest.route('GET', '/api/v1/wallet/ping', idempotency_key: false),

    'listMyPrograms' => RouteRequest.route('GET', '/api/v1/wallet/programs/me', idempotency_key: false),
    'setCollectionAnchor' => RouteRequest.route('PUT', '/api/v1/wallet/programs/:programId/collection-anchor', idempotency_key: false,
      optional: %w[collectionEndUserId reason expectedVersion]),

    'createEndUser' => RouteRequest.route('POST', '/api/v1/wallet/end-users', idempotency_key: true,
      required: %w[programId accountType phone],
      optional: %w[externalCustomerId kycRef kycLevelCache displayName corporateAccountId defaultCurrency]),
    'listEndUsers' => RouteRequest.route('GET', '/api/v1/wallet/end-users', idempotency_key: false,
      query: %w[programId accountType status corporateAccountId merchantCategoryState] + wallet_page),
    'getEndUserByExternalId' => RouteRequest.route('GET', '/api/v1/wallet/end-users/by-external/:externalCustomerId', idempotency_key: false,
      query: %w[programId]),
    'getEndUser' => RouteRequest.route('GET', '/api/v1/wallet/end-users/:endUserId', idempotency_key: false),
    'freezeEndUser' => RouteRequest.route('POST', '/api/v1/wallet/end-users/:endUserId/freeze', idempotency_key: true, optional: %w[reason]),
    'getBalances' => RouteRequest.route('GET', '/api/v1/wallet/end-users/:endUserId/balances', idempotency_key: false),
    'getKycLevel' => RouteRequest.route('GET', '/api/v1/wallet/end-users/:endUserId/kyc-level', idempotency_key: false),
    'updateKycLevel' => RouteRequest.route('PUT', '/api/v1/wallet/end-users/:endUserId/kyc-level', idempotency_key: true,
      required: %w[kycLevel sourceRef],
      optional: %w[externalCustomerId programId reason effectiveAt expectedCurrentLevel]),
    'getLimits' => RouteRequest.route('GET', '/api/v1/wallet/end-users/:endUserId/limits', idempotency_key: false, query: %w[operationType currency]),
    'createWallet' => RouteRequest.route('POST', '/api/v1/wallet/end-users/:endUserId/wallets', idempotency_key: true, optional: %w[name currencies]),

    'createWalletAccount' => RouteRequest.route('POST', '/api/v1/wallet/wallets/:walletId/accounts', idempotency_key: true, required: %w[currency]),
    'lookupWallet' => RouteRequest.route('POST', '/api/v1/wallet/wallets/lookup', idempotency_key: false, optional: %w[programId phone walletNo]),

    'listDepositInstructions' => RouteRequest.route('GET', '/api/v1/wallet/end-users/:endUserId/deposit-instructions', idempotency_key: false),
    'createDepositInstruction' => RouteRequest.route('POST', '/api/v1/wallet/end-users/:endUserId/deposit-instructions', idempotency_key: false,
      required: %w[walletAccountId],
      optional: %w[currency]),
    'simulateInboundCredit' => RouteRequest.route('POST', '/api/v1/wallet/bank-integrations/inbound-credits', idempotency_key: false,
      required: %w[programId railId amount currency rawReference],
      optional: %w[senderName senderIban creditedIban receiptNumber]),

    'createCorporateAccount' => RouteRequest.route('POST', '/api/v1/wallet/corporate-accounts', idempotency_key: true,
      required: %w[programId code name ownerEndUserId],
      optional: %w[fundingCurrency]),
    'listCorporateAccounts' => RouteRequest.route('GET', '/api/v1/wallet/corporate-accounts', idempotency_key: false,
      query: %w[programId status] + wallet_page),
    'importCorporateEmployees' => RouteRequest.route('POST', '/api/v1/wallet/corporate-accounts/:corporateAccountId/employees/import',
      idempotency_key: true, required: %w[rows]),
    'offboardCorporateEmployees' => RouteRequest.route('POST', '/api/v1/wallet/corporate-accounts/:corporateAccountId/employees/offboard',
      idempotency_key: true, required: %w[rows], optional: %w[reason]),

    'quoteFees' => RouteRequest.route('POST', '/api/v1/wallet/fees/quote', idempotency_key: false,
      required: %w[programId operationType currency amount], optional: %w[at]),

    'quoteW2W' => RouteRequest.route('POST', '/api/v1/wallet/transfers/w2w/quote', idempotency_key: false,
      required: money_move, optional: %w[destinationWalletNo destinationPhone paymentPurpose]),
    'initiateW2W' => RouteRequest.route('POST', '/api/v1/wallet/transfers/w2w', idempotency_key: true,
      required: money_move,
      optional: %w[destinationWalletNo destinationPhone paymentPurpose] + initiate_extra),
    'completeW2W' => RouteRequest.route('POST', '/api/v1/wallet/transfers/w2w/:operationId/complete', idempotency_key: true,
      required: complete_required, optional: complete_optional),

    'quoteW2Iban' => RouteRequest.route('POST', '/api/v1/wallet/transfers/w2iban/quote', idempotency_key: false,
      required: iban_move, optional: %w[bankCode paymentPurpose]),
    'initiateW2Iban' => RouteRequest.route('POST', '/api/v1/wallet/transfers/w2iban', idempotency_key: true,
      required: iban_move, optional: %w[bankCode paymentPurpose] + initiate_extra),
    'completeW2Iban' => RouteRequest.route('POST', '/api/v1/wallet/transfers/w2iban/:operationId/complete', idempotency_key: true,
      required: complete_required, optional: complete_optional),

    'quoteBankWithdrawal' => RouteRequest.route('POST', '/api/v1/wallet/withdrawals/bank/quote', idempotency_key: false,
      required: iban_move, optional: %w[bankCode paymentPurpose]),
    'initiateBankWithdrawal' => RouteRequest.route('POST', '/api/v1/wallet/withdrawals/bank', idempotency_key: true,
      required: iban_move, optional: %w[bankCode paymentPurpose] + initiate_extra),
    'completeBankWithdrawal' => RouteRequest.route('POST', '/api/v1/wallet/withdrawals/bank/:operationId/complete', idempotency_key: true,
      required: complete_required,
      optional: complete_optional),
    'getWithdrawal' => RouteRequest.route('GET', '/api/v1/wallet/withdrawals/:operationId', idempotency_key: false),

    'listOperations' => RouteRequest.route('GET', '/api/v1/wallet/operations', idempotency_key: false,
      query: %w[endUserId walletAccountId status operationType destinationWalletAccountId] + wallet_page),
    'getOperation' => RouteRequest.route('GET', '/api/v1/wallet/operations/:operationId', idempotency_key: false),
    'getOperationReceipt' => RouteRequest.route('GET', '/api/v1/wallet/operations/:operationId/receipt', idempotency_key: false),

    'startCardTopup' => RouteRequest.route('POST', '/api/v1/wallet/topups/card', idempotency_key: true,
      required: %w[creditWalletAccountId amount currency],
      optional: %w[fundingMerchantId savedCardUserKey savedCardToken savedConsumerToken
      savedPublicCardStorageToken returnUrl]),
    'getTopup' => RouteRequest.route('GET', '/api/v1/wallet/topups/:operationId', idempotency_key: false),
    # The gateway DTO marks approverPrincipal optional, but the wallet service refuses the refund without
    # it (400 WALLET_VALIDATION): it is required in practice.
    'refundTopup' => RouteRequest.route('POST', '/api/v1/wallet/topups/:operationId/refund', idempotency_key: false,
      required: %w[reason requesterPrincipal approverPrincipal]),
    'agentTopup' => RouteRequest.route('POST', '/api/v1/wallet/agent-topups', idempotency_key: true,
      required: %w[agentId creditWalletAccountId amount currency]),

    'requestPayment' => RouteRequest.route('POST', '/api/v1/wallet/payments/buy', idempotency_key: true,
      required: %w[amount currency paymentPurpose],
      optional: %w[buyerWalletNo buyerPhone orderRef cashierRef otpDestination otpChannel locale]),
    'approvePayment' => RouteRequest.route('POST', '/api/v1/wallet/payments/:operationId/approve', idempotency_key: true,
      required: %w[buyerEndUserId integrityHash nonce],
      optional: complete_optional),
    'collectByCode' => RouteRequest.route('POST', '/api/v1/wallet/collect', idempotency_key: true,
      required: %w[code amount currency], optional: %w[orderRef paymentPurpose locale]),
    'getPayment' => RouteRequest.route('GET', '/api/v1/wallet/payments/:operationId', idempotency_key: false),
    'getBusinessCommission' => RouteRequest.route('GET', '/api/v1/wallet/business-accounts/:businessAccountId/commission', idempotency_key: false),

    'createQr' => RouteRequest.route('POST', '/api/v1/wallet/qr', idempotency_key: true,
      required: %w[qrType currency],
      optional: %w[targetEndUserId targetExternalCustomerId programId amount expiresInSeconds metadata]),
    'listQr' => RouteRequest.route('GET', '/api/v1/wallet/qr', idempotency_key: false, query: %w[programId qrType status targetEndUserId] + wallet_page),
    'getQr' => RouteRequest.route('GET', '/api/v1/wallet/qr/:qrId', idempotency_key: false),
    'getQrImage' => RouteRequest.route('GET', '/api/v1/wallet/qr/:qrId/image', idempotency_key: false, binary: true, query: %w[format scale]),
    'revokeQr' => RouteRequest.route('POST', '/api/v1/wallet/qr/:qrId/revoke', idempotency_key: false),
    'parseQr' => RouteRequest.route('POST', '/api/v1/wallet/qr/parse', idempotency_key: false, required: %w[payload]),

    'createBulkPayout' => RouteRequest.route('POST', '/api/v1/wallet/bulk-payouts', idempotency_key: true,
      required: %w[programId sourceWalletAccountId currency items], optional: %w[reason]),
    'listBulkPayouts' => RouteRequest.route('GET', '/api/v1/wallet/bulk-payouts', idempotency_key: false, query: %w[programId status limit]),
    'getBulkPayout' => RouteRequest.route('GET', '/api/v1/wallet/bulk-payouts/:batchId', idempotency_key: false),
    'listBulkPayoutItems' => RouteRequest.route('GET', '/api/v1/wallet/bulk-payouts/:batchId/items', idempotency_key: false, query: %w[status limit]),
    'submitBulkPayout' => RouteRequest.route('POST', '/api/v1/wallet/bulk-payouts/:batchId/submit', idempotency_key: false),
    'approveBulkPayout' => RouteRequest.route('POST', '/api/v1/wallet/bulk-payouts/:batchId/approve', idempotency_key: false,
      required: %w[approve], optional: %w[reason]),
    'rejectBulkPayout' => RouteRequest.route('POST', '/api/v1/wallet/bulk-payouts/:batchId/reject', idempotency_key: false, optional: %w[reason]),
    'processBulkPayout' => RouteRequest.route('POST', '/api/v1/wallet/bulk-payouts/:batchId/process', idempotency_key: false),
    'retryFailedBulkPayout' => RouteRequest.route('POST', '/api/v1/wallet/bulk-payouts/:batchId/retry-failed', idempotency_key: false)
  }.freeze
end
