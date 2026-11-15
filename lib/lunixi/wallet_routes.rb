# frozen_string_literal: true

module Lunixi
  wallet_page = %w[limit cursor].freeze
  money_move = %w[endUserId sourceWalletAccountId amount currency].freeze
  iban_move = %w[endUserId sourceWalletAccountId beneficiaryName iban amount currency].freeze
  initiate_extra = %w[scheduleVersionId otpDestination otpChannel locale].freeze
  complete_required = %w[endUserId operationId integrityHash nonce].freeze
  complete_optional = %w[otpCode trustedActionToken].freeze
  # Every path below is relative to /api/v1/wallet.
  route = ->(method, path, **fields) { RouteRequest.route(method, "/api/v1/wallet#{path}", **fields) }

  # Every wallet route the SDK calls: method, path template, whether the gateway requires an
  # Idempotency-Key, the body fields it accepts (required / optional; forbidNonWhitelisted, so any other
  # field is a 400) and the query parameters. The same table as the Node SDK's WALLET_ROUTES; the parity
  # test compares it with the shared catalog field by field.
  WALLET_ROUTES = {
    'ping' => route.call('GET', '/ping', idempotency_key: false),

    'listMyPrograms' => route.call('GET', '/programs/me', idempotency_key: false),
    'setCollectionAnchor' => route.call('PUT', '/programs/:programId/collection-anchor',
                                        idempotency_key: false, optional: %w[collectionEndUserId reason expectedVersion]),

    'createEndUser' => route.call('POST', '/end-users',
                                  idempotency_key: true, required: %w[programId accountType phone],
                                  optional: %w[externalCustomerId kycRef kycLevelCache displayName corporateAccountId defaultCurrency]),
    'listEndUsers' => route.call('GET', '/end-users',
                                 idempotency_key: false, query: %w[programId accountType status corporateAccountId merchantCategoryState] + wallet_page),
    'getEndUserByExternalId' => route.call('GET', '/end-users/by-external/:externalCustomerId', idempotency_key: false, query: %w[programId]),
    'getEndUser' => route.call('GET', '/end-users/:endUserId', idempotency_key: false),
    'freezeEndUser' => route.call('POST', '/end-users/:endUserId/freeze', idempotency_key: true, optional: %w[reason]),
    'getBalances' => route.call('GET', '/end-users/:endUserId/balances', idempotency_key: false),
    'getKycLevel' => route.call('GET', '/end-users/:endUserId/kyc-level', idempotency_key: false),
    'updateKycLevel' => route.call('PUT', '/end-users/:endUserId/kyc-level',
                                   idempotency_key: true, required: %w[kycLevel sourceRef],
                                   optional: %w[externalCustomerId programId reason effectiveAt expectedCurrentLevel]),
    'getLimits' => route.call('GET', '/end-users/:endUserId/limits', idempotency_key: false, query: %w[operationType currency]),
    'createWallet' => route.call('POST', '/end-users/:endUserId/wallets', idempotency_key: true, optional: %w[name currencies]),

    'createWalletAccount' => route.call('POST', '/wallets/:walletId/accounts', idempotency_key: true, required: %w[currency]),
    'lookupWallet' => route.call('POST', '/wallets/lookup', idempotency_key: false, optional: %w[programId phone walletNo]),

    'listDepositInstructions' => route.call('GET', '/end-users/:endUserId/deposit-instructions', idempotency_key: false),
    'createDepositInstruction' => route.call('POST', '/end-users/:endUserId/deposit-instructions',
                                             idempotency_key: false, required: %w[walletAccountId], optional: %w[currency]),
    'simulateInboundCredit' => route.call('POST', '/bank-integrations/inbound-credits',
                                          idempotency_key: false, required: %w[programId railId amount currency rawReference],
                                          optional: %w[senderName senderIban creditedIban receiptNumber]),

    'createCorporateAccount' => route.call('POST', '/corporate-accounts',
                                           idempotency_key: true, required: %w[programId code name ownerEndUserId], optional: %w[fundingCurrency]),
    'listCorporateAccounts' => route.call('GET', '/corporate-accounts', idempotency_key: false, query: %w[programId status] + wallet_page),
    'importCorporateEmployees' => route.call('POST', '/corporate-accounts/:corporateAccountId/employees/import', idempotency_key: true, required: %w[rows]),
    'offboardCorporateEmployees' => route.call('POST', '/corporate-accounts/:corporateAccountId/employees/offboard',
                                               idempotency_key: true, required: %w[rows], optional: %w[reason]),

    'quoteFees' => route.call('POST', '/fees/quote', idempotency_key: false, required: %w[programId operationType currency amount], optional: %w[at]),

    'quoteW2W' => route.call('POST', '/transfers/w2w/quote',
                             idempotency_key: false, required: money_move, optional: %w[destinationWalletNo destinationPhone paymentPurpose]),
    'initiateW2W' => route.call('POST', '/transfers/w2w',
                                idempotency_key: true, required: money_move,
                                optional: %w[destinationWalletNo destinationPhone paymentPurpose] + initiate_extra),
    'completeW2W' => route.call('POST', '/transfers/w2w/:operationId/complete',
                                idempotency_key: true, required: complete_required, optional: complete_optional),

    'quoteW2Iban' => route.call('POST', '/transfers/w2iban/quote', idempotency_key: false, required: iban_move, optional: %w[bankCode paymentPurpose]),
    'initiateW2Iban' => route.call('POST', '/transfers/w2iban',
                                   idempotency_key: true, required: iban_move, optional: %w[bankCode paymentPurpose] + initiate_extra),
    'completeW2Iban' => route.call('POST', '/transfers/w2iban/:operationId/complete',
                                   idempotency_key: true, required: complete_required, optional: complete_optional),

    'quoteBankWithdrawal' => route.call('POST', '/withdrawals/bank/quote', idempotency_key: false, required: iban_move, optional: %w[bankCode paymentPurpose]),
    'initiateBankWithdrawal' => route.call('POST', '/withdrawals/bank',
                                           idempotency_key: true, required: iban_move, optional: %w[bankCode paymentPurpose] + initiate_extra),
    'completeBankWithdrawal' => route.call('POST', '/withdrawals/bank/:operationId/complete',
                                           idempotency_key: true, required: complete_required, optional: complete_optional),
    'getWithdrawal' => route.call('GET', '/withdrawals/:operationId', idempotency_key: false),

    'listOperations' => route.call('GET', '/operations',
                                   idempotency_key: false, query: %w[endUserId walletAccountId status operationType destinationWalletAccountId] + wallet_page),
    'getOperation' => route.call('GET', '/operations/:operationId', idempotency_key: false),
    'getOperationReceipt' => route.call('GET', '/operations/:operationId/receipt', idempotency_key: false),

    'startCardTopup' => route.call('POST', '/topups/card',
                                   idempotency_key: true, required: %w[creditWalletAccountId amount currency],
                                   optional: %w[fundingMerchantId savedCardUserKey savedCardToken savedConsumerToken savedPublicCardStorageToken returnUrl]),
    'getTopup' => route.call('GET', '/topups/:operationId', idempotency_key: false),
    # The gateway DTO marks approverPrincipal optional, but the wallet service refuses the refund without
    # it (400 WALLET_VALIDATION): it is required in practice.
    'refundTopup' => route.call('POST', '/topups/:operationId/refund', idempotency_key: false, required: %w[reason requesterPrincipal approverPrincipal]),
    'agentTopup' => route.call('POST', '/agent-topups', idempotency_key: true, required: %w[agentId creditWalletAccountId amount currency]),

    'requestPayment' => route.call('POST', '/payments/buy',
                                   idempotency_key: true, required: %w[amount currency paymentPurpose],
                                   optional: %w[buyerWalletNo buyerPhone orderRef cashierRef otpDestination otpChannel locale]),
    'approvePayment' => route.call('POST', '/payments/:operationId/approve',
                                   idempotency_key: true, required: %w[buyerEndUserId integrityHash nonce], optional: complete_optional),
    'collectByCode' => route.call('POST', '/collect', idempotency_key: true, required: %w[code amount currency], optional: %w[orderRef paymentPurpose locale]),
    'getPayment' => route.call('GET', '/payments/:operationId', idempotency_key: false),
    'getBusinessCommission' => route.call('GET', '/business-accounts/:businessAccountId/commission', idempotency_key: false),

    'createQr' => route.call('POST', '/qr',
                             idempotency_key: true, required: %w[qrType currency],
                             optional: %w[targetEndUserId targetExternalCustomerId programId amount expiresInSeconds metadata]),
    'listQr' => route.call('GET', '/qr', idempotency_key: false, query: %w[programId qrType status targetEndUserId] + wallet_page),
    'getQr' => route.call('GET', '/qr/:qrId', idempotency_key: false),
    'getQrImage' => route.call('GET', '/qr/:qrId/image', idempotency_key: false, binary: true, query: %w[format scale]),
    'revokeQr' => route.call('POST', '/qr/:qrId/revoke', idempotency_key: false),
    'parseQr' => route.call('POST', '/qr/parse', idempotency_key: false, required: %w[payload]),

    'createBulkPayout' => route.call('POST', '/bulk-payouts',
                                     idempotency_key: true, required: %w[programId sourceWalletAccountId currency items], optional: %w[reason]),
    'listBulkPayouts' => route.call('GET', '/bulk-payouts', idempotency_key: false, query: %w[programId status limit]),
    'getBulkPayout' => route.call('GET', '/bulk-payouts/:batchId', idempotency_key: false),
    'listBulkPayoutItems' => route.call('GET', '/bulk-payouts/:batchId/items', idempotency_key: false, query: %w[status limit]),
    'submitBulkPayout' => route.call('POST', '/bulk-payouts/:batchId/submit', idempotency_key: false),
    'approveBulkPayout' => route.call('POST', '/bulk-payouts/:batchId/approve', idempotency_key: false, required: %w[approve], optional: %w[reason]),
    'rejectBulkPayout' => route.call('POST', '/bulk-payouts/:batchId/reject', idempotency_key: false, optional: %w[reason]),
    'processBulkPayout' => route.call('POST', '/bulk-payouts/:batchId/process', idempotency_key: false),
    'retryFailedBulkPayout' => route.call('POST', '/bulk-payouts/:batchId/retry-failed', idempotency_key: false)
  }.freeze
end
