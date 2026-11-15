# frozen_string_literal: true

require_relative 'test_helper'

class PaymentValuesTest < Minitest::Test
  def setup
    @transport = RecordingTransport.new { response }
    @sdk = client(transport: @transport)
  end

  def test_payment_method_action_and_provider_selection_values
    assert_equal %w[CARD BNPL SHOPPING_LOAN PROMISSORY_NOTE MEAL_CARD GIFT_CARD CASH CASH_ON_DELIVERY WALLET BANK_TRANSFER
                    OPEN_BANKING MOBILE_BILLING QR_CODE CRYPTO OTHER], Lunixi::PaymentMethod::ALL
    assert_equal({ 'QR' => 'QR_CODE' }, Lunixi::PaymentMethod::ALIASES)
    assert_equal %w[OTP REDIRECT DISPLAY APP_APPROVAL INPUT], Lunixi::PaymentActionType::ALL
    assert_equal %w[ROUTED OPTIONAL REQUIRED], Lunixi::ProviderSelection::ALL
    assert_equal %w[BUYER PLATFORM], Lunixi::ProviderSelectionMode::ALL
  end

  def test_field_lists
    assert_equal %w[mobileBilling wallet promissoryNote mealCard openBanking shoppingLoan bankTransfer], Lunixi::METHOD_BLOCK_FIELDS
    assert_equal %w[card installment installmentQuoteToken force3D], Lunixi::CARD_ONLY_FIELDS
    assert_equal %w[otp consentAccepted fields], Lunixi::PAYMENT_ACTION_CONFIRM_FIELDS
    assert_equal %w[mobileBilling wallet promissoryNote], Lunixi::SPLIT_LEG_BLOCK_FIELDS
    assert_equal %w[status currency createdFrom createdTo orderId ownerRef limit after], Lunixi::LIST_SPLIT_PAYMENTS_FILTERS
    assert_equal 100, Lunixi::SHOPPING_LOAN_MAX_BASKET_ITEMS
    assert_equal 24, Lunixi::PROMISSORY_NOTE_MAX_SCHEDULE_ITEMS
    assert_equal Lunixi::METHOD_BLOCK_FIELDS, Lunixi::DIRECT_METHOD_PAYMENT_FIELDS.last(7)
    %w[paymentMethod amount currency orderId callbackUrl basketItems card force3D metadata].each do |field|
      assert_includes Lunixi::DIRECT_METHOD_PAYMENT_FIELDS, field
    end
    refute_includes Lunixi::DIRECT_METHOD_PAYMENT_FIELDS, 'price'
  end

  def test_bank_transfer_promissory_note_and_split_values
    assert_equal '9999', Lunixi::BANK_TRANSFER_OTHER_BANKS_CODE
    assert_equal 200, Lunixi::BANK_TRANSFER_EXCEPTION_LIMIT_MAX
    assert_equal %w[LATE UNDERPAID OVERPAID], Lunixi::PaymentBankTransferExceptionKind::ALL
    assert_equal %w[PENDING_DECISION ACCEPTED REFUND_PENDING REFUNDED], Lunixi::PaymentBankTransferExceptionStatus::ALL
    assert_equal %w[ISSUED PAID PROTESTED CANCELLED], Lunixi::PromissoryNoteStatus::ALL
    assert_equal %w[PROMISSORY_NOTE PAYMENT_ORDER], Lunixi::PromissoryNoteDocumentType::ALL
    assert_equal %w[CANCELLED ALREADY_CLOSED NOT_CANCELLABLE FAILED], Lunixi::PromissoryNoteCancelResult::ALL
    assert_equal %w[payment.promissory_note.not_cancellable payment.promissory_note.provider_unavailable payment.promissory_note.cancel_rejected],
                 Lunixi::PromissoryNoteCancelErrorCode::ALL
    assert_equal %w[tr-TR en-GB], Lunixi::PromissoryNoteDocumentLocale::ALL
  end

  def test_event_names
    assert_equal %w[payment.bank_transfer.partially_received payment.bank_transfer.underpaid payment.bank_transfer.overpaid
                    payment.bank_transfer.late_arrival], Lunixi::PaymentBankTransferEvents::ALL
    assert_equal %w[payment.promissory_note.paid payment.promissory_note.protested payment.promissory_note.cancelled],
                 Lunixi::PromissoryNoteEvents::ALL
    assert_equal %w[payment.split.completed payment.split.voided payment.split.compensating payment.split.outcome_pending
                    payment.split.reconciliation_required payment.split.leg_refund_pending], Lunixi::SplitPaymentEvents::ALL
    assert_equal 'payment.split.leg_events', Lunixi::SPLIT_LEG_EVENTS_SUBSCRIPTION
  end

  def test_list_payment_methods_maps_qr_and_rejects_invalid_codes_locally
    ['qr_code', 'Mobile', '', 'A' * 33, 5].each do |code|
      assert_raises(Lunixi::ConfigurationError) { @sdk.payments.list_payment_methods(payment_method: code) }
    end
    assert_empty @transport.calls
    @sdk.payments.list_payment_methods(payment_method: 'QR')
    request = @transport.calls.last
    assert_equal '/api/v1/payments/methods', request[:uri].path
    assert_equal 'paymentMethod=QR_CODE', request[:uri].query
    assert request[:headers].key?('X-Signature')
    @sdk.payments.methods
    assert_nil @transport.calls.last[:uri].query
  end

  def test_reference_address_dictionary
    ['6', '00', '82', 6].each do |code|
      assert_raises(Lunixi::ConfigurationError) { @sdk.reference.list_districts(code) }
    end
    ['', '12a', '1' * 13].each do |code|
      assert_raises(Lunixi::ConfigurationError) { @sdk.reference.list_neighborhoods(code) }
    end
    assert_empty @transport.calls
    @sdk.reference.list_provinces
    @sdk.reference.list_districts('06')
    @sdk.reference.list_neighborhoods('1234')
    requests = @transport.calls.drop(1)
    assert_equal(%w[/api/v1/reference/tr-address/provinces /api/v1/reference/tr-address/districts /api/v1/reference/tr-address/neighborhoods],
                 requests.map { |request| request[:uri].path })
    assert_equal([nil, 'provinceCode=06', 'districtCode=1234'], requests.map { |request| request[:uri].query })
  end

  def test_bank_transfer_instruction_reads_display_action_only
    instruction = { 'bankCode' => '0062', 'bankName' => 'Bank', 'holderName' => 'Merchant Ltd', 'iban' => 'TR000000000000000000000000',
                    'amountMinor' => '10000', 'currency' => 'TRY', 'paymentCode' => 'LNX123', 'expiresAt' => '2026-11-16T12:00:00Z',
                    'otherBank' => false }
    envelope = { 'data' => { 'paymentId' => 'pay_1', 'action' => { 'id' => 'act_1', 'type' => 'DISPLAY', 'bankTransfer' => instruction } } }
    result = Lunixi::BankTransferInstruction.from_response(envelope)
    assert_equal '0062', result.bank_code
    assert_equal 'TR000000000000000000000000', result.iban
    assert_equal '10000', result.amount_minor
    assert_equal 'LNX123', result.payment_code
    assert_equal false, result.other_bank
    assert_equal result, Lunixi::BankTransferInstruction.from_response(envelope['data'])
    assert_nil Lunixi::BankTransferInstruction.from_response({ 'data' => { 'paymentId' => 'pay_1' } })
    assert_nil Lunixi::BankTransferInstruction.from_response({ 'data' => { 'action' => { 'type' => 'OTP', 'bankTransfer' => instruction } } })
    assert_nil Lunixi::BankTransferInstruction.from_response({ 'data' => { 'action' => { 'type' => 'DISPLAY' } } })
    assert_nil Lunixi::BankTransferInstruction.from_response(nil)
  end
end
