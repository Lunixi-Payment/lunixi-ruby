# frozen_string_literal: true

module Lunixi
  # Wallet values (/api/v1/wallet, product WALLET_SERVICE); the route table is in wallet_routes.rb.
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
end
