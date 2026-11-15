# frozen_string_literal: true

module Lunixi
  # Closed value sets of the payment-link API (/api/v1/payments/links). The gateway answers an unknown
  # value with 400.
  module PaymentLinkUsage
    # Can be paid once: an invoice or a personal payment request.
    SINGLE_USE = 'SINGLE_USE'
    # Can be paid many times: donations, tickets, a product page.
    MULTI_USE = 'MULTI_USE'

    ALL = [SINGLE_USE, MULTI_USE].freeze
  end

  module PaymentLinkAmountMode
    # The merchant sets the amount (amountMinor).
    FIXED = 'FIXED'
    # The buyer enters the amount, bounded by minAmountMinor / maxAmountMinor.
    OPEN = 'OPEN'
    # The buyer picks quantities from items; the amount is the sum of the lines.
    ITEMIZED = 'ITEMIZED'

    ALL = [FIXED, OPEN, ITEMIZED].freeze
  end

  module PaymentLinkState
    ACTIVE = 'ACTIVE'
    PAUSED = 'PAUSED'
    COMPLETED = 'COMPLETED'
    EXPIRED = 'EXPIRED'
    DEACTIVATED = 'DEACTIVATED'
    # Removed by Lunixi. Every write on the link answers 409 payment_link.link.taken_down.
    TAKEN_DOWN = 'TAKEN_DOWN'

    ALL = [ACTIVE, PAUSED, COMPLETED, EXPIRED, DEACTIVATED, TAKEN_DOWN].freeze
  end

  module PaymentLinkAttemptState
    OPEN = 'OPEN'
    BOUND = 'BOUND'
    SUCCEEDED = 'SUCCEEDED'
    FAILED = 'FAILED'
    EXPIRED = 'EXPIRED'
    ABANDONED = 'ABANDONED'
    NEEDS_REVIEW = 'NEEDS_REVIEW'

    ALL = [OPEN, BOUND, SUCCEEDED, FAILED, EXPIRED, ABANDONED, NEEDS_REVIEW].freeze
  end

  module PaymentLinkEnvironment
    TEST = 'TEST'
    LIVE = 'LIVE'

    ALL = [TEST, LIVE].freeze
  end

  module BuyerFieldRequirement
    HIDDEN = 'HIDDEN'
    OPTIONAL = 'OPTIONAL'
    REQUIRED = 'REQUIRED'

    ALL = [HIDDEN, OPTIONAL, REQUIRED].freeze
  end

  module CustomFieldType
    TEXT = 'TEXT'
    NUMBER = 'NUMBER'
    EMAIL = 'EMAIL'
    PHONE = 'PHONE'
    DATE = 'DATE'
    SELECT = 'SELECT'
    CHECKBOX = 'CHECKBOX'
    TCKN = 'TCKN'
    VKN = 'VKN'

    ALL = [TEXT, NUMBER, EMAIL, PHONE, DATE, SELECT, CHECKBOX, TCKN, VKN].freeze
  end

  module PaymentLinkButtonLabel
    PAY = 'PAY'
    DONATE = 'DONATE'
    BUY = 'BUY'
    BOOK = 'BOOK'

    ALL = [PAY, DONATE, BUY, BOOK].freeze
  end

  module PaymentLinkDeliveryChannel
    EMAIL = 'EMAIL'
    SMS = 'SMS'

    ALL = [EMAIL, SMS].freeze
  end

  module PaymentLinkQrFormat
    SVG = 'svg'
    PNG = 'png'

    ALL = [SVG, PNG].freeze
  end

  module PaymentLinkLocale
    TR = 'tr'
    EN = 'en'

    ALL = [TR, EN].freeze
  end

  # Types a payment-link image can be declared as. On confirmation the stored file's own bytes are
  # checked against the declared type; SVG is never accepted.
  module PaymentLinkImageContentType
    PNG = 'image/png'
    JPEG = 'image/jpeg'
    WEBP = 'image/webp'

    ALL = [PNG, JPEG, WEBP].freeze
  end

  # Every field of a payment-link definition in the gateway's spelling. Create and update bodies may
  # carry only these keys (plus environment on create); the gateway rejects any other key with 400.
  PAYMENT_LINK_SPEC_FIELDS = %w[
    usage amountMode currency amountMinor minAmountMinor maxAmountMinor suggestedAmountsMinor quantityEnabled
    minQuantity maxQuantity items capacity title description imageAssetId successMessage successRedirectUrl taxNote
    locale startsAt expiresAt eventAt buttonLabelKey requireTermsAcceptance buyerFields customFields recipient prefill
    verification reminders checkout reference tags branchCode salesChannel campaign agentCode merchantNotifyEmails
    metadata
  ].freeze

  # Fixed when the link is created; an update that names one answers 422 payment_link.link.immutable_field.
  PAYMENT_LINK_IMMUTABLE_FIELDS = %w[usage amountMode currency].freeze

  # Shape of a media asset id (a UUID); ownership and state are checked by the gateway.
  PAYMENT_LINK_ASSET_ID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
end
