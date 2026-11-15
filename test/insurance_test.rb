# frozen_string_literal: true

require_relative 'test_helper'

# Insurance I1–I22: fields and filters are checked before sending, the Idempotency-Key rule per route,
# policy files and the reconciliation export as bytes. Ids and values are synthetic.
class InsuranceTest < Minitest::Test
  PAYMENT = '0d8f6b1c-1111-4222-8333-444455556666'
  ORDER = 'inso_0123456789abcdef0123456789abcdef'
  KEY = 'insurance-key-0001'
  SECRET = 'whsec_synthetic_test_only'

  def setup
    @transport = RecordingTransport.new { response(200, { 'data' => { 'orderId' => ORDER } }) }
    @insurance = client(transport: @transport).insurance
  end

  def test_create_quote_sends_the_type_body_as_given
    tickets = [{ basketItemId: 'item_1', transportMode: 'BUS', anyTypeField: 'kept' }]
    @insurance.create_quote({ insuranceType: 'TICKET_CANCELLATION', currency: 'try', payment_intent_id: PAYMENT, tickets: tickets })
    call = api_calls(@transport).fetch(0)
    assert_equal ['POST', '/api/v1/insurance/quotes'], [call[:method], call[:uri].path]
    assert call[:headers].key?('X-Signature')
    refute call[:headers].key?('Idempotency-Key')
    body = sent_json(call)
    assert_equal ['TICKET_CANCELLATION', 'TRY', PAYMENT], body.values_at('insuranceType', 'currency', 'paymentIntentId')
    assert_equal 'kept', body['tickets'][0]['anyTypeField']
  end

  def test_quote_basket_is_payment_or_items_not_both
    items = { items: [{ id: 'item_1', name: 'Ticket', price: '50000' }] }
    error = assert_raises(Lunixi::ConfigurationError) do
      @insurance.create_quote({ insuranceType: 'TICKET_CANCELLATION', currency: 'TRY', paymentIntentId: PAYMENT, context: items })
    end
    assert_match(/not both/, error.message)
    @insurance.create_quote({ insuranceType: 'TICKET_CANCELLATION', currency: 'TRY', context: items }, idempotency_key: KEY)
    assert_equal KEY, api_calls(@transport).fetch(0)[:headers]['Idempotency-Key']
    @insurance.create_quote({ insuranceType: 'FOREIGN_RESIDENT_HEALTH', currency: 'TRY', residence: { city: '34' } })
    assert_equal 2, api_calls(@transport).size
  end

  def test_idempotency_key_rules
    consent = { termsVersion: 'v1', termsSha256: 'a' * 64, acceptedAt: '2026-10-31T11:59:00Z' }
    [
      -> { @insurance.create_order({ quoteId: 'insq_1', consent: consent }) },
      -> { @insurance.create_order({ quoteId: 'insq_1', consent: consent }, idempotency_key: 'short') },
      -> { @insurance.issue_policy(ORDER) },
      -> { @insurance.cancel_order(ORDER) },
      -> { @insurance.refund_premium(ORDER) },
      -> { @insurance.confirm_payment(ORDER, external_payment) },
      -> { @insurance.create_lead({ insuranceType: 'CARGO' }) },
      -> { @insurance.bind_payment(ORDER, PAYMENT, idempotency_key: 'has space x') }
    ].each { |call| assert_raises(Lunixi::ConfigurationError) { call.call } }
    assert_empty api_calls(@transport)

    @insurance.create_order({ quoteId: 'insq_1', consent: consent }, idempotency_key: KEY)
    @insurance.issue_policy(ORDER, idempotency_key: KEY)
    @insurance.bind_payment(ORDER, PAYMENT)
    calls = api_calls(@transport)
    assert_equal(['/api/v1/insurance/orders', "/api/v1/insurance/orders/#{ORDER}/issue-policy", "/api/v1/insurance/orders/#{ORDER}/bind-payment"],
                 calls.map { |call| call[:uri].path })
    assert_equal([KEY, KEY, nil], calls.map { |call| call[:headers]['Idempotency-Key'] })
    assert_nil calls[1][:body]
  end

  def test_confirm_payment_and_refund_bodies
    @insurance.confirm_payment(ORDER, external_payment, idempotency_key: KEY)
    assert_equal({ 'payment' => { 'externalPaymentId' => 'ext_1', 'paidAmount' => '4990', 'paidCurrency' => 'TRY',
                                  'paidAt' => '2026-10-31T11:00:00.000Z' } }, sent_json(api_calls(@transport).fetch(0)))
    @insurance.refund_premium(ORDER, external_refund: { externalRefundId: 'r_1', refundedAt: '2026-10-31T12:00:00Z' }, idempotency_key: KEY)
    assert_equal({ 'externalRefund' => { 'externalRefundId' => 'r_1', 'refundedAt' => '2026-10-31T12:00:00Z' } },
                 sent_json(api_calls(@transport).fetch(1)))
    assert_raises(Lunixi::ConfigurationError) { @insurance.confirm_payment(ORDER, external_payment.merge(paidAmount: 4990), idempotency_key: KEY) }
    assert_raises(Lunixi::ConfigurationError) { @insurance.confirm_payment(ORDER, external_payment.merge(amount: '1'), idempotency_key: KEY) }
  end

  def test_filters_are_checked
    @insurance.list_products(currency: 'TRY', paymentIntentId: PAYMENT)
    assert_equal({ 'currency' => 'TRY', 'paymentIntentId' => PAYMENT }, URI.decode_www_form(api_calls(@transport).fetch(0)[:uri].query).to_h)
    [
      -> { @insurance.list_products(paymentIntentId: PAYMENT) },
      -> { @insurance.list_products(currency: 'TRY', paymentIntentId: 'not-a-uuid') },
      -> { @insurance.list_orders(limit: 0) },
      -> { @insurance.list_leads(status: 'DONE') },
      -> { @insurance.get_reconciliation_summary(from: '2026-10-01T00:00:00Z') },
      -> { @insurance.list_reference_values('PLANET') },
      -> { @insurance.list_orders(environment: 'LIVE') }
    ].each { |call| assert_raises(Lunixi::ConfigurationError) { call.call } }
    assert_equal 1, api_calls(@transport).size
  end

  def test_policy_files_are_bytes
    pdf = "%PDF-1.7\n\xFF\x00".b
    transport = RecordingTransport.new { response(200, pdf, 'content-type' => 'application/pdf') }
    insurance = client(transport: transport).insurance
    assert_equal pdf, insurance.get_policy_document('insp_1')
    assert_equal pdf, insurance.get_policy_receipt('insp_1')
    assert_equal pdf, insurance.get_policy_certificate('insp_1')
    calls = api_calls(transport)
    assert_equal(%w[document receipt certificate].map { |file| "/api/v1/insurance/policies/insp_1/#{file}" }, calls.map { |call| call[:uri].path })
    assert(calls.all? { |call| call[:headers]['Accept'].start_with?('application/pdf') })
  end

  def test_reconciliation_export_reads_the_trailer
    csv = "﻿orderId,policyId\ninso_1,insp_1\n# truncated=true orderCap=20000 nextCursor=abc123\n".b
    transport = RecordingTransport.new { response(200, csv, 'content-type' => 'text/csv') }
    export = client(transport: transport).insurance.export_reconciliation(from: '2026-10-01T00:00:00Z', to: '2026-11-01T00:00:00Z')
    assert_equal csv, export.data
    assert export.truncated?
    assert_equal 'abc123', export.next_cursor
    refute export.aborted?
    transport = RecordingTransport.new { response(200, "orderId\n# export-aborted=true\n", 'content-type' => 'text/csv') }
    assert client(transport: transport).insurance.export_reconciliation(from: '2026-10-01T00:00:00Z', to: '2026-11-01T00:00:00Z').aborted?
  end

  def test_create_lead_keeps_the_note_as_given
    @insurance.create_lead({ insuranceType: 'CARGO', policyholder: { name: 'X' }, note: '  call after 5pm ' }, idempotency_key: KEY)
    assert_equal '  call after 5pm ', sent_json(api_calls(@transport).fetch(0))['note']
    assert_raises(Lunixi::ConfigurationError) { @insurance.create_lead({ insuranceType: 'CARGO', note: 'x' * 1001 }, idempotency_key: KEY) }
    assert_raises(Lunixi::ConfigurationError) { @insurance.create_lead({ insuranceType: 'CARGO', currency: 'TRY' }, idempotency_key: KEY) }
  end

  def test_helpers
    consent = Lunixi::Insurance.consent_from_quote({ 'terms' => { 'version' => 'v1', 'sha256' => 'abc' } }, Time.utc(2026, 10, 31, 11))
    assert_equal({ 'termsVersion' => 'v1', 'termsSha256' => 'abc', 'acceptedAt' => '2026-10-31T11:00:00.000Z' }, consent)
    assert_raises(Lunixi::ConfigurationError) { Lunixi::Insurance.consent_from_quote({}, Time.now) }
    order = { 'orderId' => ORDER, 'premiumCollectedBy' => 'MERCHANT', 'premiumAmount' => '4990' }
    item = Lunixi::Insurance.premium_basket_item(order, name: 'Ticket insurance', category1: 'Insurance')
    assert_equal({ 'id' => ORDER, 'name' => 'Ticket insurance', 'category1' => 'Insurance', 'itemType' => 'VIRTUAL', 'price' => '4990' }, item)
    assert_raises(Lunixi::ConfigurationError) do
      Lunixi::Insurance.premium_basket_item(order.merge('premiumCollectedBy' => 'PROVIDER'), name: 'x', category1: 'y')
    end
  end

  def test_order_and_lead_webhooks
    verifier = Lunixi::WebhookVerifier.new(secret: SECRET, clock: -> { NOW })
    data = { eventId: 'evt_1', insuranceOrderId: ORDER, premiumAmount: '4990', policies: [{ policyId: 'insp_1', documentUrl: '' }], secret: 'x' }
    body, headers = signed_webhook({ id: 'evt_1', type: Lunixi::InsuranceEvents::POLICY_ISSUED, data: data }, SECRET)
    event = Lunixi::InsuranceWebhook.parse(body, headers, verifier)
    assert_equal ORDER, event['insuranceOrderId']
    refute event.data.key?('secret')
    refute Lunixi::InsuranceWebhook.lead_event?(event)
    body, headers = signed_webhook({ id: 'evt_2', type: Lunixi::InsuranceEvents::LEAD_SUBMITTED, data: { lead: { leadId: 'insl_1' } } },
                                   SECRET, event_id: 'evt_2')
    lead = Lunixi::InsuranceWebhook.from_event(verifier.verify(body, headers))
    assert_equal 'insl_1', lead['lead']['leadId']
    assert_equal Lunixi::INSURANCE_LEAD_WEBHOOK_FIELDS, lead.data.keys
    assert Lunixi::InsuranceWebhook.lead_event?(lead)
  end

  private

  def external_payment
    { externalPaymentId: 'ext_1', paidAmount: '4990', paidCurrency: 'TRY', paidAt: Time.utc(2026, 10, 31, 11) }
  end
end
