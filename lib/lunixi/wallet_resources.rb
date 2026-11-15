# frozen_string_literal: true

module Lunixi
  # wallet.programs
  class WalletPrograms
    def initialize(invoker)
      @invoker = invoker
    end

    # The wallet programs of the signing merchant.
    def list_mine
      @invoker.page('listMyPrograms')
    end

    # Sets the end user whose wallet collects the program's merchant payments; leaving
    # collection_end_user_id out clears the anchor.
    def set_collection_anchor(program_id, collection_end_user_id: nil, reason: nil, expected_version: nil)
      body = { 'collectionEndUserId' => collection_end_user_id, 'reason' => reason, 'expectedVersion' => expected_version }
      @invoker.data('setCollectionAnchor', params: { 'programId' => program_id }, body: RouteRequest.compact(body))
    end
  end

  # wallet.end_users
  class WalletEndUsers
    def initialize(invoker)
      @invoker = invoker
    end

    # Creates an end user and their default wallet (Idempotency-Key required).
    def create(request, idempotency_key: nil)
      @invoker.data('createEndUser', body: request, idempotency_key: idempotency_key)
    end

    def list(**filters)
      @invoker.page('listEndUsers', query: filters)
    end

    def iterate(**filters, &block)
      RouteRequest.each_item(filters, block) { |query| list(**query) }
    end

    def get(end_user_id)
      @invoker.data('getEndUser', params: { 'endUserId' => end_user_id })
    end

    # Finds an end user by your own customer id.
    def get_by_external_id(external_customer_id, program_id: nil)
      @invoker.data('getEndUserByExternalId', params: { 'externalCustomerId' => external_customer_id },
                                              query: RouteRequest.compact('programId' => program_id))
    end

    # Freezes the end user (POST /end-users/{id}/freeze). Named freeze_end_user so Object#freeze is
    # left alone (the catalog operation is wallet.endUsers.freeze).
    def freeze_end_user(end_user_id, reason: nil, idempotency_key: nil)
      @invoker.data('freezeEndUser', params: { 'endUserId' => end_user_id }, body: RouteRequest.compact('reason' => reason),
                                     idempotency_key: idempotency_key)
    end

    def get_balances(end_user_id)
      @invoker.data('getBalances', params: { 'endUserId' => end_user_id })
    end

    def get_kyc_level(end_user_id)
      @invoker.data('getKycLevel', params: { 'endUserId' => end_user_id })
    end

    # Records the KYC level from your own verification (sourceRef: your KYC session id).
    def update_kyc_level(end_user_id, request, idempotency_key: nil)
      @invoker.data('updateKycLevel', params: { 'endUserId' => end_user_id }, body: request, idempotency_key: idempotency_key)
    end

    # Limit usage per operation type; operation_type and currency narrow the answer.
    def get_limits(end_user_id, operation_type: nil, currency: nil)
      @invoker.data('getLimits', params: { 'endUserId' => end_user_id },
                                 query: RouteRequest.compact('operationType' => operation_type, 'currency' => currency))
    end

    def create_wallet(end_user_id, name: nil, currencies: nil, idempotency_key: nil)
      @invoker.data('createWallet', params: { 'endUserId' => end_user_id },
                                    body: RouteRequest.compact('name' => name, 'currencies' => currencies), idempotency_key: idempotency_key)
    end
  end

  # wallet.wallets
  class WalletAccounts
    def initialize(invoker)
      @invoker = invoker
    end

    # Adds a currency account to a wallet.
    def create_account(wallet_id, currency, idempotency_key: nil)
      @invoker.data('createWalletAccount', params: { 'walletId' => wallet_id }, body: { 'currency' => currency }, idempotency_key: idempotency_key)
    end

    # Resolves a wallet number or phone to { exists, walletNo, maskedName } before a transfer.
    def lookup(request)
      @invoker.data('lookupWallet', body: request)
    end
  end

  # wallet.deposits: bank transfer details an end user pays into to top up.
  class WalletDeposits
    def initialize(invoker)
      @invoker = invoker
    end

    def list_instructions(end_user_id)
      @invoker.data('listDepositInstructions', params: { 'endUserId' => end_user_id })
    end

    def create_instruction(end_user_id, wallet_account_id: nil, currency: nil)
      @invoker.data('createDepositInstruction', params: { 'endUserId' => end_user_id },
                                                body: RouteRequest.compact('walletAccountId' => wallet_account_id, 'currency' => currency))
    end

    # Test only: books an incoming bank transfer as the bank rail would.
    def simulate_inbound_credit(request)
      @invoker.data('simulateInboundCredit', body: request)
    end
  end

  # wallet.corporate
  class WalletCorporate
    def initialize(invoker)
      @invoker = invoker
    end

    def create(request, idempotency_key: nil)
      @invoker.data('createCorporateAccount', body: request, idempotency_key: idempotency_key)
    end

    def list(**filters)
      @invoker.page('listCorporateAccounts', query: filters)
    end

    def iterate(**filters, &block)
      RouteRequest.each_item(filters, block) { |query| list(**query) }
    end

    # Imports up to 1000 employees at once; all or nothing (a 422 writes nothing). rows: [{ phone, ... }].
    def import_employees(corporate_account_id, rows, idempotency_key: nil)
      @invoker.data('importCorporateEmployees', params: { 'corporateAccountId' => corporate_account_id }, body: { 'rows' => rows },
                                                idempotency_key: idempotency_key)
    end

    def offboard_employees(corporate_account_id, rows, reason: nil, idempotency_key: nil)
      @invoker.data('offboardCorporateEmployees', params: { 'corporateAccountId' => corporate_account_id },
                                                  body: RouteRequest.compact('rows' => rows, 'reason' => reason), idempotency_key: idempotency_key)
    end
  end

  # wallet.fees
  class WalletFees
    def initialize(invoker)
      @invoker = invoker
    end

    # The fee, tax and total charge an operation would cost.
    def quote(request)
      @invoker.data('quoteFees', body: request)
    end
  end

  # wallet.transfers: money moves in two steps. initiate_* reserves the limit and answers
  # { operationId, integrityHash, nonce, otpRequired, ... }; complete_* with the same integrityHash and
  # nonce (and the OTP when otpRequired) commits it. Quote first to show the fee; pass its
  # scheduleVersionId to initiate_* to hold that fee. complete_* puts operationId in the body itself.
  class WalletTransfers
    def initialize(invoker)
      @invoker = invoker
    end

    def quote_w2w(request)
      @invoker.data('quoteW2W', body: request)
    end

    def initiate_w2w(request, idempotency_key: nil)
      @invoker.data('initiateW2W', body: request, idempotency_key: idempotency_key)
    end

    def complete_w2w(operation_id, request, idempotency_key: nil)
      complete('completeW2W', operation_id, request, idempotency_key)
    end

    def quote_w2_iban(request)
      @invoker.data('quoteW2Iban', body: request)
    end

    def initiate_w2_iban(request, idempotency_key: nil)
      @invoker.data('initiateW2Iban', body: request, idempotency_key: idempotency_key)
    end

    def complete_w2_iban(operation_id, request, idempotency_key: nil)
      complete('completeW2Iban', operation_id, request, idempotency_key)
    end

    private

    def complete(name, operation_id, request, key)
      body = @invoker.with_operation_id(name, operation_id, request)
      @invoker.data(name, params: { 'operationId' => operation_id }, body: body, idempotency_key: key)
    end
  end

  # wallet.withdrawals: to the end user's own bank account, in the same two steps as transfers.
  class WalletWithdrawals
    def initialize(invoker)
      @invoker = invoker
    end

    def quote(request)
      @invoker.data('quoteBankWithdrawal', body: request)
    end

    def initiate(request, idempotency_key: nil)
      @invoker.data('initiateBankWithdrawal', body: request, idempotency_key: idempotency_key)
    end

    def complete(operation_id, request, idempotency_key: nil)
      body = @invoker.with_operation_id('completeBankWithdrawal', operation_id, request)
      @invoker.data('completeBankWithdrawal', params: { 'operationId' => operation_id }, body: body, idempotency_key: idempotency_key)
    end

    # { operation, history }
    def get(operation_id)
      @invoker.data('getWithdrawal', params: { 'operationId' => operation_id })
    end
  end

  # wallet.operations
  class WalletOperations
    def initialize(invoker)
      @invoker = invoker
    end

    def list(**filters)
      @invoker.page('listOperations', query: filters)
    end

    def iterate(**filters, &block)
      RouteRequest.each_item(filters, block) { |query| list(**query) }
    end

    # { operation, history }
    def get(operation_id)
      @invoker.data('getOperation', params: { 'operationId' => operation_id })
    end

    def get_receipt(operation_id)
      @invoker.data('getOperationReceipt', params: { 'operationId' => operation_id })
    end
  end

  # wallet.topups
  class WalletTopups
    def initialize(invoker)
      @invoker = invoker
    end

    # Starts a card top-up. Render checkoutFormContent (or follow redirectUrl / threeDsHtml); the wallet is
    # credited when the payment completes (wallet.topup.completed).
    def start_card(request, idempotency_key: nil)
      @invoker.data('startCardTopup', body: request, idempotency_key: idempotency_key)
    end

    # { operation, history }
    def get(operation_id)
      @invoker.data('getTopup', params: { 'operationId' => operation_id })
    end

    # Refunds a card top-up to the card. Four eyes: approverPrincipal is required and must differ from
    # requesterPrincipal; binding them to two real people is your approval flow's job.
    def refund(operation_id, request)
      @invoker.data('refundTopup', params: { 'operationId' => operation_id }, body: request)
    end

    # Cash top-up through an agent of the program.
    def agent(request, idempotency_key: nil)
      @invoker.data('agentTopup', body: request, idempotency_key: idempotency_key)
    end
  end

  # wallet.payments: the end user pays the merchant. The creditor is the wallet terminal bound to the
  # signing key (403 WALLET_TERMINAL_* without one); a businessAccountId in the body is refused.
  class WalletPayments
    def initialize(invoker)
      @invoker = invoker
    end

    # Asks the buyer (by wallet number or phone) to pay; approve it with approve.
    def request(request, idempotency_key: nil)
      @invoker.data('requestPayment', body: request, idempotency_key: idempotency_key)
    end

    def approve(operation_id, request, idempotency_key: nil)
      @invoker.data('approvePayment', params: { 'operationId' => operation_id }, body: request, idempotency_key: idempotency_key)
    end

    # Collects with the payment code the buyer shows (customer-presented).
    def collect(request, idempotency_key: nil)
      @invoker.data('collectByCode', body: request, idempotency_key: idempotency_key)
    end

    # { operation, history }
    def get(operation_id)
      @invoker.data('getPayment', params: { 'operationId' => operation_id })
    end

    def get_commission(business_account_id)
      @invoker.data('getBusinessCommission', params: { 'businessAccountId' => business_account_id })
    end
  end

  # wallet.qr
  class WalletQr
    def initialize(invoker)
      @invoker = invoker
    end

    # Static QR codes carry no amount; dynamic ones require it.
    def create(request, idempotency_key: nil)
      @invoker.data('createQr', body: request, idempotency_key: idempotency_key)
    end

    def list(**filters)
      @invoker.page('listQr', query: filters)
    end

    def iterate(**filters, &block)
      RouteRequest.each_item(filters, block) { |query| list(**query) }
    end

    def get(qr_id)
      @invoker.data('getQr', params: { 'qrId' => qr_id })
    end

    # The QR image as frozen bytes: format svg (the default) or png (WalletQrImageFormat), scale 1–20.
    def image(qr_id, format: nil, scale: nil)
      unless format.nil? || WalletQrImageFormat::ALL.include?(format)
        raise ConfigurationError, "QR image format must be one of #{WalletQrImageFormat::ALL.join(', ')}."
      end
      raise ConfigurationError, 'QR image scale must be an integer 1-20.' unless scale.nil? || (scale.is_a?(Integer) && scale.between?(1, 20))

      @invoker.call('getQrImage', params: { 'qrId' => qr_id }, query: RouteRequest.compact('format' => format, 'scale' => scale))
    end

    def revoke(qr_id)
      @invoker.data('revokeQr', params: { 'qrId' => qr_id })
    end

    # Decodes a scanned QR payload.
    def parse(payload)
      @invoker.data('parseQr', body: { 'payload' => payload })
    end
  end

  # wallet.bulk_payouts: maker-checker. The approver must be a different key than the creator (the
  # principal is the signing key id). Creating needs wallet:bulk:create; submit, approve, process and
  # retry_failed need wallet:bulk:approve.
  class WalletBulkPayouts
    def initialize(invoker)
      @invoker = invoker
    end

    def create(request, idempotency_key: nil)
      @invoker.data('createBulkPayout', body: request, idempotency_key: idempotency_key)
    end

    def list(**filters)
      @invoker.page('listBulkPayouts', query: filters)
    end

    def get(batch_id)
      @invoker.data('getBulkPayout', params: { 'batchId' => batch_id })
    end

    def list_items(batch_id, **filters)
      @invoker.page('listBulkPayoutItems', params: { 'batchId' => batch_id }, query: filters)
    end

    def submit(batch_id)
      @invoker.data('submitBulkPayout', params: { 'batchId' => batch_id })
    end

    # approve: false declines the batch with reason.
    def approve(batch_id, approve: true, reason: nil)
      @invoker.data('approveBulkPayout', params: { 'batchId' => batch_id }, body: RouteRequest.compact('approve' => approve, 'reason' => reason))
    end

    def reject(batch_id, reason: nil)
      @invoker.data('rejectBulkPayout', params: { 'batchId' => batch_id }, body: RouteRequest.compact('reason' => reason))
    end

    def process(batch_id)
      @invoker.data('processBulkPayout', params: { 'batchId' => batch_id })
    end

    def retry_failed(batch_id)
      @invoker.data('retryFailedBulkPayout', params: { 'batchId' => batch_id })
    end
  end
end
