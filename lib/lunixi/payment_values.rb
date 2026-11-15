# frozen_string_literal: true

module Lunixi
  # Public payment method codes (paymentMethod). QR is accepted as an alias of QR_CODE.
  module PaymentMethod
    CARD = 'CARD'
    BNPL = 'BNPL'
    SHOPPING_LOAN = 'SHOPPING_LOAN'
    PROMISSORY_NOTE = 'PROMISSORY_NOTE'
    MEAL_CARD = 'MEAL_CARD'
    GIFT_CARD = 'GIFT_CARD'
    CASH = 'CASH'
    CASH_ON_DELIVERY = 'CASH_ON_DELIVERY'
    WALLET = 'WALLET'
    BANK_TRANSFER = 'BANK_TRANSFER'
    OPEN_BANKING = 'OPEN_BANKING'
    # Charge to the buyer's mobile phone bill.
    MOBILE_BILLING = 'MOBILE_BILLING'
    QR_CODE = 'QR_CODE'
    CRYPTO = 'CRYPTO'
    OTHER = 'OTHER'

    ALL = [CARD, BNPL, SHOPPING_LOAN, PROMISSORY_NOTE, MEAL_CARD, GIFT_CARD, CASH, CASH_ON_DELIVERY, WALLET,
           BANK_TRANSFER, OPEN_BANKING, MOBILE_BILLING, QR_CODE, CRYPTO, OTHER].freeze
    ALIASES = { 'QR' => QR_CODE }.freeze
  end

  # What the buyer must do when a payment response carries data.action (action.type).
  module PaymentActionType
    # Send the one-time code with payments.confirm_payment_action.
    OTP = 'OTP'
    # Send the buyer to action.redirect.url (for cards: the bank's 3D Secure page).
    REDIRECT = 'REDIRECT'
    # Show the buyer something to act on outside the page (transfer details, a code).
    DISPLAY = 'DISPLAY'
    # The buyer approves in the provider's app; the result arrives by webhook.
    APP_APPROVAL = 'APP_APPROVAL'
    # Send the fields listed in action.input.fields with payments.confirm_payment_action.
    INPUT = 'INPUT'

    ALL = [OTP, REDIRECT, DISPLAY, APP_APPROVAL, INPUT].freeze
  end

  # providerSelection of a method in payments.list_payment_methods.
  module ProviderSelection
    # Card: routing picks the provider; providerCode is not sent.
    ROUTED = 'ROUTED'
    # providerCode may be omitted: one provider is connected, or the platform picks it.
    OPTIONAL = 'OPTIONAL'
    # The buyer picks the brand and more than one provider is connected; providerCode must be sent.
    REQUIRED = 'REQUIRED'

    ALL = [ROUTED, OPTIONAL, REQUIRED].freeze
  end

  # providerSelectionMode of a method in payments.list_payment_methods: who picks the provider.
  module ProviderSelectionMode
    # The buyer picks the brand; with more than one provider connected providerCode is required.
    BUYER = 'BUYER'
    # The buyer does not pick a brand; without providerCode the platform picks a connected provider.
    PLATFORM = 'PLATFORM'

    ALL = [BUYER, PLATFORM].freeze
  end

  # Method blocks POST /payments/direct/payment accepts besides card. The block of the chosen
  # method is required; a block for another method is rejected. A method without a block here
  # cannot be paid through direct/payment yet.
  METHOD_BLOCK_FIELDS = %w[mobileBilling wallet promissoryNote mealCard openBanking shoppingLoan bankTransfer].freeze

  # Body fields of POST /payments/direct/payment.
  DIRECT_METHOD_PAYMENT_FIELDS = (%w[
    paymentMethod amount currency orderId paymentChannel paymentGroup callbackUrl locale description customerId
    preauth buyer shippingAddress billingAddress basketItems card installment installmentQuoteToken force3D metadata
  ] + METHOD_BLOCK_FIELDS).freeze

  # Fields that belong to a card payment only (paymentMethod CARD).
  CARD_ONLY_FIELDS = %w[card installment installmentQuoteToken force3D].freeze

  # Body fields of POST /payments/{paymentId}/actions/{actionId}/confirm a merchant server sends.
  # The hosted form's checkout token fields are never sent by this SDK.
  PAYMENT_ACTION_CONFIRM_FIELDS = %w[otp consentAccepted fields].freeze

  # Most basket items a SHOPPING_LOAN payment can carry; the basket is required for that method.
  SHOPPING_LOAN_MAX_BASKET_ITEMS = 100
end
