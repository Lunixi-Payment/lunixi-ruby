# frozen_string_literal: true

require_relative 'test_helper'

class PromissoryNoteBankTransferTest < Minitest::Test
  PDF = "%PDF-1.7\n\xE2\xE3\xCF\xD3\n%%EOF".b.freeze
  EXCEPTION_ID = '0f8fad5b-d9cb-469f-a165-70867728950e'

  def setup
    @transport = RecordingTransport.new do |request|
      if request[:uri].path.end_with?('/document')
        Lunixi::Response.new(status: 200, headers: { 'content-type' => 'application/pdf' }, body: PDF.dup)
      else
        response(200, { 'data' => nil })
      end
    end
    @sdk = client(transport: @transport)
  end

  def test_promissory_note_list_and_cancel
    @sdk.payments.get_promissory_notes('pay_1')
    list = @transport.calls.last
    assert_equal ['GET', '/api/v1/payments/pay_1/promissory-notes'], [list[:method], list[:uri].path]
    assert list[:headers].key?('X-Signature')

    @sdk.payments.cancel_promissory_notes('pay_1')
    assert_nil @transport.calls.last[:body]
    @sdk.payments.cancel_promissory_notes('pay_1', serial_numbers: %w[SN-0001 SN-0002])
    cancel = @transport.calls.last
    assert_equal '/api/v1/payments/pay_1/promissory-notes/cancel', cancel[:uri].path
    assert_equal '{"serialNumbers":["SN-0001","SN-0002"]}', cancel[:body]
    assert cancel[:headers].key?('X-Signature')
  end

  def test_promissory_note_serial_numbers_are_checked
    calls = @transport.calls.size
    [[], ['abc'], ['SN 0001'], ['x' * 65], [1234], Array.new(25) { |index| format('SN-%04d', index) }, 'SN-0001'].each do |serials|
      assert_raises(Lunixi::ConfigurationError) { @sdk.payments.cancel_promissory_notes('pay_1', serial_numbers: serials) }
    end
    assert_raises(Lunixi::ConfigurationError) { @sdk.payments.get_promissory_notes('') }
    assert_equal calls, @transport.calls.size
  end

  def test_promissory_note_document_returns_pdf_bytes
    pdf = @sdk.payments.download_promissory_note_document('pay_1', locale: Lunixi::PromissoryNoteDocumentLocale::EN)
    assert_equal PDF, pdf
    assert_equal Encoding::BINARY, pdf.encoding
    assert_predicate pdf, :frozen?
    request = @transport.calls.last
    assert_equal '/api/v1/payments/pay_1/promissory-notes/document', request[:uri].path
    assert_equal 'locale=en-GB', request[:uri].query
    assert_equal 'application/pdf, application/json', request[:headers]['Accept']
    assert request[:headers].key?('X-Signature')
    @sdk.payments.download_promissory_note_document('pay_1')
    assert_nil @transport.calls.last[:uri].query
    ['tr', 'de-DE', 'TR-tr', ''].each do |locale|
      assert_raises(Lunixi::ConfigurationError) { @sdk.payments.download_promissory_note_document('pay_1', locale: locale) }
    end
  end

  def test_promissory_note_document_error_is_a_json_envelope
    transport = RecordingTransport.new { response(503, { 'code' => 'payment.promissory_note.document_unavailable' }) }
    sdk = client(transport: transport, max_retries: 0)
    error = assert_raises(Lunixi::ApiError) { sdk.payments.download_promissory_note_document('pay_1') }
    assert_equal 503, error.status
    assert_equal 'payment.promissory_note.document_unavailable', error.code
  end

  def test_bank_transfer_exception_filters
    [{ environment: 'PROD' }, { limit: 0 }, { limit: 201 }, { limit: '10' }, { status: 'OPEN' }].each do |filters|
      assert_raises(Lunixi::ConfigurationError) { @sdk.payments.list_bank_transfer_exceptions(**filters) }
    end
    assert_empty @transport.calls

    @sdk.payments.list_bank_transfer_exceptions
    assert_nil @transport.calls.last[:uri].query
    @sdk.payments.list_bank_transfer_exceptions(environment: 'LIVE', status: Lunixi::PaymentBankTransferExceptionStatus::PENDING_DECISION, limit: 200)
    request = @transport.calls.last
    assert_equal '/api/v1/payments/bank-transfer/exceptions', request[:uri].path
    assert_equal 'environment=LIVE&status=PENDING_DECISION&limit=200', request[:uri].query
    assert request[:headers].key?('X-Signature')
  end

  def test_bank_transfer_exception_decisions
    ['', 'exception_1', "#{EXCEPTION_ID}x", EXCEPTION_ID.delete('-')].each do |id|
      assert_raises(Lunixi::ConfigurationError) { @sdk.payments.accept_bank_transfer_exception(id) }
      assert_raises(Lunixi::ConfigurationError) { @sdk.payments.mark_bank_transfer_exception_refunded(id) }
    end
    assert_empty @transport.calls

    assert_nil @sdk.payments.accept_bank_transfer_exception(EXCEPTION_ID.upcase)['data']
    @sdk.payments.mark_bank_transfer_exception_refunded(EXCEPTION_ID)
    accept, refunded = @transport.calls.drop(1)
    assert_equal "/api/v1/payments/bank-transfer/exceptions/#{EXCEPTION_ID.upcase}/accept", accept[:uri].path
    assert_equal "/api/v1/payments/bank-transfer/exceptions/#{EXCEPTION_ID}/refunded", refunded[:uri].path
    [accept, refunded].each do |request|
      assert_equal 'POST', request[:method]
      assert_nil request[:body]
      assert request[:headers].key?('X-Signature')
    end
  end

  def test_split_legs_only_carry_leg_blocks
    card = { amount: '5000', cardToken: 'stored_token' }
    [
      { paymentMethod: 'BANK_TRANSFER', amount: '5000', bankTransfer: { bankCode: '0062' } },
      { paymentMethod: 'OPEN_BANKING', amount: '5000', openBanking: { providerCode: 'bank_a' } },
      { paymentMethod: 'MEAL_CARD', amount: '5000', mealCard: { providerCode: 'meal_a' } },
      { paymentMethod: 'SHOPPING_LOAN', amount: '5000', shoppingLoan: { providerCode: 'loan_a' } },
      { paymentMethod: 'WALLET', amount: '5000', wallet: { providerCode: 'wallet_a' }, mobileBilling: { providerCode: 'gsm_a' } },
      { paymentMethod: 'WALLET', amount: '5000' },
      { paymentMethod: 'PROMISSORY_NOTE', amount: '5000', promissoryNote: { providerCode: 'note_a', schedule: [] } },
      { amount: '5000', cardToken: 'stored_token_2', wallet: { providerCode: 'wallet_a' } }
    ].each do |leg|
      body = { totalAmount: '10000', currency: 'TRY', ownerRef: 'owner_1', legs: [card, leg] }
      assert_raises(Lunixi::ConfigurationError) { @sdk.payments.split(body, idempotency_key: idempotency_key) }
    end
    assert_empty @transport.calls

    wallet = { paymentMethod: 'WALLET', amount: '5000', wallet: { providerCode: 'wallet_a', gsmNumber: '+905321234567' } }
    body = { totalAmount: '10000', currency: 'TRY', ownerRef: 'owner_1', legs: [card, wallet], basketItems: [basket_item('10000')] }
    error = assert_raises(Lunixi::ConfigurationError) { @sdk.payments.split(body, idempotency_key: idempotency_key) }
    assert_equal 'A split payment requires the order details: buyer, billingAddress, shippingAddress.', error.message
    assert_empty @transport.calls
    @sdk.payments.split(body.merge(order_details), idempotency_key: idempotency_key)
    assert_equal '/api/v1/payments/split', @transport.calls.last[:uri].path
    sent = JSON.parse(@transport.calls.last[:body])
    assert_empty sent.keys - Lunixi::SPLIT_PAYMENT_FIELDS
    assert_equal({ 'city' => 'Istanbul' }, sent.fetch('billingAddress').slice('city'))
  end

  def test_list_splits_filters
    [{ status: 'PAID' }, { currency: 'try' }, { limit: 0 }, { limit: 101 }, { createdFrom: 'yesterday' }, { unknown: 'x' },
     { status: Array.new(21) { 'COMPLETED' } }].each do |filters|
      assert_raises(Lunixi::ConfigurationError) { @sdk.payments.list_splits(**filters) }
    end
    assert_empty @transport.calls

    @sdk.payments.list_splits(status: %w[COMPLETED VOIDED], currency: 'TRY', createdFrom: '2026-11-01', limit: 25, after: 'cursor_1')
    request = @transport.calls.last
    assert_equal '/api/v1/payments/split', request[:uri].path
    assert_equal 'status=COMPLETED&status=VOIDED&currency=TRY&createdFrom=2026-11-01&limit=25&after=cursor_1', request[:uri].query
    @sdk.payments.get_split('split_1')
    assert_equal '/api/v1/payments/split/split_1', @transport.calls.last[:uri].path
  end
end
