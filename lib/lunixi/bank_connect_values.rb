# frozen_string_literal: true

module Lunixi
  # Bank accounts (/api/v1/bank-connect, product BANK_CONNECT): value sets, filters, the transfer and FX
  # routes and the webhook events.

  # Status of a bank connection. Data is read only while a connection is ACTIVE or DEGRADED (DEGRADED:
  # the last reads from the bank failed, so the data may be older; see the account's freshness).
  module BankConnectionStatus
    PENDING_DOCUMENTS = 'PENDING_DOCUMENTS'
    UNDER_REVIEW = 'UNDER_REVIEW'
    PENDING_SETUP = 'PENDING_SETUP'
    ACTIVE = 'ACTIVE'
    DEGRADED = 'DEGRADED'
    SUSPENDED = 'SUSPENDED'
    DISCONNECTED = 'DISCONNECTED'
    ALL = [PENDING_DOCUMENTS, UNDER_REVIEW, PENDING_SETUP, ACTIVE, DEGRADED, SUSPENDED, DISCONNECTED].freeze
  end

  module BankAccountStatus
    ACTIVE = 'ACTIVE'
    INACTIVE = 'INACTIVE'
    ALL = [ACTIVE, INACTIVE].freeze
  end

  # Money in (CREDIT) or out (DEBIT). amountMinor is always positive.
  module BankTransactionDirection
    CREDIT = 'CREDIT'
    DEBIT = 'DEBIT'
    ALL = [CREDIT, DEBIT].freeze
  end

  # The bank-independent transaction type (canonicalType).
  module BankTransactionType
    TRANSFER_IN = 'TRANSFER_IN'
    TRANSFER_OUT = 'TRANSFER_OUT'
    INTERNAL_IN = 'INTERNAL_IN'
    INTERNAL_OUT = 'INTERNAL_OUT'
    POS_SETTLEMENT = 'POS_SETTLEMENT'
    POS_SETTLEMENT_REFUND = 'POS_SETTLEMENT_REFUND'
    FEE = 'FEE'
    TAX = 'TAX'
    CASH_IN = 'CASH_IN'
    CASH_OUT = 'CASH_OUT'
    CARD = 'CARD'
    LOAN = 'LOAN'
    FX = 'FX'
    INTEREST = 'INTEREST'
    OTHER = 'OTHER'
    ALL = [TRANSFER_IN, TRANSFER_OUT, INTERNAL_IN, INTERNAL_OUT, POS_SETTLEMENT, POS_SETTLEMENT_REFUND, FEE, TAX, CASH_IN, CASH_OUT,
           CARD, LOAN, FX, INTEREST, OTHER].freeze
  end

  # AVAILABLE: the bank can be connected (connections are started in the Lunixi dashboard).
  module BankAvailability
    AVAILABLE = 'AVAILABLE'
    COMING_SOON = 'COMING_SOON'
    ALL = [AVAILABLE, COMING_SOON].freeze
  end

  # What a bank or a connection offers. OUTGOING_TRANSFER and FX_EXCHANGE open bank_connect.transfers and
  # bank_connect.fx.
  module BankCapability
    ACCOUNT_LIST = 'ACCOUNT_LIST'
    BALANCE = 'BALANCE'
    TRANSACTIONS = 'TRANSACTIONS'
    OUTGOING_TRANSFER = 'OUTGOING_TRANSFER'
    FX_EXCHANGE = 'FX_EXCHANGE'
    ALL = [ACCOUNT_LIST, BALANCE, TRANSACTIONS, OUTGOING_TRANSFER, FX_EXCHANGE].freeze
  end

  # QUEUED: the read starts now or is already waiting. SCHEDULED: it runs at scheduledAt.
  module BankSyncStatus
    QUEUED = 'QUEUED'
    SCHEDULED = 'SCHEDULED'
    ALL = [QUEUED, SCHEDULED].freeze
  end

  # Bank-account webhook events (subscription bank_account.*). TRANSACTION_RECEIVED: a new transaction
  # (CREDIT or DEBIT) was read from a connected account by a regular read after the connection became
  # active; the history loaded when an account is first connected sends none. Read it with
  # Lunixi::BankConnectWebhook.parse; the event id is the same on every redelivery.
  module BankConnectEvents
    TRANSACTION_RECEIVED = 'bank_account.transaction.received'
    PATTERN = 'bank_account.*'
    ALL = [TRANSACTION_RECEIVED].freeze
  end

  # Status of an outgoing transfer. PENDING_OTP: started in the dashboard, waiting for the user's code (an
  # API-key transfer never has it). SUBMITTED: queued or sent to the bank. COMPLETED can still become
  # RETURNED. FAILED, RETURNED and CANCELED are final.
  module BankTransferStatus
    PENDING_OTP = 'PENDING_OTP'
    SUBMITTED = 'SUBMITTED'
    PROCESSING = 'PROCESSING'
    COMPLETED = 'COMPLETED'
    FAILED = 'FAILED'
    RETURNED = 'RETURNED'
    CANCELED = 'CANCELED'
    ALL = [PENDING_OTP, SUBMITTED, PROCESSING, COMPLETED, FAILED, RETURNED, CANCELED].freeze
  end

  # The rail the bank chose; UNKNOWN until it says.
  module BankTransferRail
    INTERNAL = 'INTERNAL'
    INTRABANK = 'INTRABANK'
    FAST = 'FAST'
    EFT = 'EFT'
    UNKNOWN = 'UNKNOWN'
    ALL = [INTERNAL, INTRABANK, FAST, EFT, UNKNOWN].freeze
  end

  module BankTransferInitiatedVia
    PANEL = 'PANEL'
    API = 'API'
    ALL = [PANEL, API].freeze
  end

  # Status of a currency exchange order; an order is created SUBMITTED.
  module BankFxOrderStatus
    SUBMITTED = 'SUBMITTED'
    COMPLETED = 'COMPLETED'
    FAILED = 'FAILED'
    ALL = [SUBMITTED, COMPLETED, FAILED].freeze
  end

  # Which amount of a quote you fixed: SOURCE (sell amount) or TARGET (buy amount).
  module BankFxRequestedSide
    SOURCE = 'SOURCE'
    TARGET = 'TARGET'
    ALL = [SOURCE, TARGET].freeze
  end

  # Bank Connect transfer webhook events (subscription bank_transfer.*), one per transfer and type. Not
  # the payment method's bank transfer events (payment.bank_transfer.*, Lunixi::PaymentBankTransferEvents).
  # Exchange orders have no webhook.
  module BankTransferEvents
    CREATED = 'bank_transfer.created'
    COMPLETED = 'bank_transfer.completed'
    FAILED = 'bank_transfer.failed'
    RETURNED = 'bank_transfer.returned'
    PATTERN = 'bank_transfer.*'
    ALL = [CREATED, COMPLETED, FAILED, RETURNED].freeze
  end

  # Query filters each read route accepts (the gateway rejects any other with 400).
  BANK_CONNECT_FILTERS = {
    'listBanks' => %w[limit cursor].freeze,
    'listConnections' => %w[limit cursor status bankId].freeze,
    'listAccounts' => %w[limit cursor connectionId bankId currency status].freeze,
    'listBalances' => %w[limit cursor accountId currency].freeze,
    'listTransactions' => %w[limit cursor accountId bookedFrom bookedTo direction minAmountMinor maxAmountMinor canonicalType].freeze
  }.freeze
  # Largest page (limit 1–100; the gateway's default is 25).
  BANK_CONNECT_MAX_LIMIT = 100
  # Most account ids one accountId filter may carry.
  BANK_CONNECT_MAX_ACCOUNT_FILTER = 100
  # Widest bookedFrom … bookedTo window of one transaction request, in days.
  BANK_CONNECT_BOOKED_RANGE_MAX_DAYS = 92
  BANK_CONNECT_CURSOR_MAX_LENGTH = 2048

  # Transfer and exchange routes: method, path, body fields, query fields and the Idempotency-Key rule.
  # The same table as the Node SDK's BANK_TRANSFER_ROUTES (forbidNonWhitelisted: any other field is a
  # 400); the parity test compares it with the shared catalog. Every route is signed and needs
  # bank-connect:transfer plus a key with an IP allowlist.
  BANK_TRANSFER_ROUTES = {
    'listTransferPurposes' => RouteRequest.route('GET', '/api/v1/bank-connect/transfer-purposes', idempotency_key: false, query: %w[connectionId]),
    'createTransfer' => RouteRequest.route('POST', '/api/v1/bank-connect/transfers', idempotency_key: true,
      required: %w[accountId receiverIban receiverName amountMinor], optional: %w[currency paymentPurpose description]),
    'listTransfers' => RouteRequest.route('GET', '/api/v1/bank-connect/transfers', idempotency_key: false,
      query: %w[limit cursor accountId status createdFrom createdTo]),
    'getTransfer' => RouteRequest.route('GET', '/api/v1/bank-connect/transfers/:transferId', idempotency_key: false),
    'listFxRates' => RouteRequest.route('GET', '/api/v1/bank-connect/fx/rates', idempotency_key: false, query: %w[connectionId]),
    'createFxQuote' => RouteRequest.route('POST', '/api/v1/bank-connect/fx/quotes', idempotency_key: false,
      required: %w[sourceAccountId targetAccountId], optional: %w[sourceAmountMinor targetAmountMinor]),
    'createFxOrder' => RouteRequest.route('POST', '/api/v1/bank-connect/fx/orders', idempotency_key: true,
      required: %w[quoteId], optional: %w[description]),
    'listFxOrders' => RouteRequest.route('GET', '/api/v1/bank-connect/fx/orders', idempotency_key: false, query: %w[limit cursor status]),
    'getFxOrder' => RouteRequest.route('GET', '/api/v1/bank-connect/fx/orders/:orderId', idempotency_key: false)
  }.freeze

  # Idempotency-Key of create_transfer / create_order: 8–200 printable ASCII characters.
  BANK_TRANSFER_IDEMPOTENCY_KEY_PATTERN = RouteRequest::PRINTABLE_IDEMPOTENCY_KEY
  # paymentPurpose: a code from transfers.list_purposes.
  BANK_TRANSFER_PAYMENT_PURPOSE_PATTERN = /\A[A-Za-z0-9_]{1,64}\z/
  BANK_TRANSFER_DESCRIPTION_MAX = 140
  BANK_TRANSFER_RECEIVER_NAME_MIN = 2
  BANK_TRANSFER_RECEIVER_NAME_MAX = 140
  # Longest receiverIban the gateway accepts (spaces included); the service checks the TR IBAN checksum.
  BANK_TRANSFER_IBAN_MAX = 42
  # Body fields that carry a minor-unit amount string.
  BANK_TRANSFER_AMOUNT_FIELDS = %w[amountMinor sourceAmountMinor targetAmountMinor].freeze

  # data fields of the bank_account.transaction.received webhook (values the bank did not send are nil).
  BANK_ACCOUNT_TRANSACTION_RECEIVED_FIELDS = %w[
    transactionId accountId connectionId bankEftCode bankName direction amountMinor currency bookedAt valueAt receivedAt
    canonicalType description counterpartyNameMasked counterpartyIbanMasked receiptNo
  ].freeze
  # data fields of a bank_transfer.* webhook (values without a value are nil).
  BANK_TRANSFER_WEBHOOK_FIELDS = %w[
    transferId connectionId accountId bankEftCode bankName status rail amountMinor currency receiverIbanMasked receiverNameMasked
    paymentPurpose description failureCode idempotencyKey createdAt completedAt failedAt returnedAt
  ].freeze
end
