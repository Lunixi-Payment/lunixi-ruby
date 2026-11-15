# frozen_string_literal: true

require_relative 'test_helper'

# Physical POS webhooks are read only after the signature, event id and timestamp verify; money is
# checked after that. Ids and values are synthetic.
class PhysicalPosWebhookTest < Minitest::Test
  SECRET = 'whsec_synthetic_test_only'

  def setup
    @verifier = Lunixi::WebhookVerifier.new(secret: SECRET, clock: -> { NOW })
  end

  def signed(envelope, event_id: 'evt_1', secret: SECRET)
    body = JSON.generate(envelope)
    timestamp = NOW.iso8601
    signature = OpenSSL::HMAC.hexdigest('SHA256', secret, "#{event_id}.#{timestamp}.#{body}")
    [body, { 'X-Lunixi-Event-Id' => event_id, 'X-Lunixi-Signature-Timestamp' => timestamp, 'X-Lunixi-Signature' => "v2=#{signature}" }]
  end

  def parse(envelope, **options)
    body, headers = signed(envelope, **options)
    Lunixi::PhysicalPos.parse_webhook_event(body, headers, @verifier)
  end

  def test_payment_event_with_cashier_and_original
    event = parse({ id: 'evt_1', type: Lunixi::PhysicalPosEvents::PAYMENT_APPROVED, environment: 'LIVE', createdAt: '2026-10-31T12:00:00Z',
                    data: { paymentId: 'p_2', operation: 'REFUND', amountMinor: '4500', historySeq: 7,
                            original: { paymentId: 'p_1', origin: 'DEVICE_DIRECT', note: 'x' },
                            cashier: { cashierId: 'c_1', cashierCode: 'K01', displayName: 'Till 1' } } })
    assert_equal ['evt_1', 'physical_pos.payment.approved', 'payment', 'LIVE', '2026-10-31T12:00:00Z', 7],
                 [event.id, event.type, event.category, event.environment, event.created_at, event.history_seq]
    assert_equal({ 'paymentId' => 'p_1', 'origin' => 'DEVICE_DIRECT' }, event.original)
    assert_equal({ 'cashierId' => 'c_1', 'cashierCode' => 'K01' }, event.cashier)
    refute event.device_sale?
    assert event.frozen?
    assert event.data.frozen?
  end

  def test_cashier_is_optional
    event = parse({ id: 'evt_1', type: 'physical_pos.payment.declined', data: { paymentId: 'p_1', historySeq: 2 } })
    assert_nil event.cashier
    assert_nil event.original
  end

  def test_device_sale
    event = parse({ id: 'evt_1', type: Lunixi::PhysicalPosEvents::PAYMENT_DEVICE_SALE,
                    data: { paymentId: 'p_1', origin: 'DEVICE_DIRECT', deviceOccurredAt: '2026-10-31T11:59:00Z', amountMinor: '100' } })
    assert event.device_sale?
    assert_equal 'payment', event.category
  end

  def test_settlement_event_has_no_history_seq
    event = parse({ id: 'evt_9', type: Lunixi::PhysicalPosEvents::SETTLEMENT_COMPLETED,
                    data: { deviceId: 'dv_1', lines: [{ reported: { saleMinor: '1000' }, difference: { saleMinor: '-50' } }] } },
                  event_id: 'evt_9')
    assert_equal ['settlement', nil, 'evt_9'], [event.category, event.history_seq, event.id]
  end

  def test_payload_json_envelope
    event = parse({ id: 'evt_1', type: 'physical_pos.fiscal_document.issued', payloadJson: JSON.generate(documentId: 'fd_1', historySeq: 1) })
    assert_equal ['fiscal_document', 'fd_1', 1], [event.category, event.data['documentId'], event.history_seq]
    assert event.data.frozen?
  end

  def test_signature_is_checked_before_the_body_is_read
    body, headers = signed({ id: 'evt_1', type: 'physical_pos.payment.approved', data: { amountMinor: 4500 } }, secret: 'whsec_other')
    assert_raises(Lunixi::WebhookError) { Lunixi::PhysicalPosWebhook.parse(body, headers, @verifier) }
  end

  def test_money_is_checked_after_the_signature
    assert_raises(Lunixi::WebhookError) { parse({ id: 'evt_1', type: 'physical_pos.payment.approved', data: { amountMinor: 4500 } }) }
  end

  def test_other_products_and_empty_payloads_are_refused
    assert_raises(Lunixi::WebhookError) { parse({ id: 'evt_1', type: 'payment.captured', data: { amount: '100' } }) }
    assert_raises(Lunixi::WebhookError) { parse({ id: 'evt_1', type: 'physical_pos.payment.approved', data: {} }) }
    assert_raises(Lunixi::WebhookError) { parse({ id: 'evt_1', type: 'physical_pos.payment.approved', payloadJson: '{' }) }
  end

  def test_a_secret_builds_the_verifier
    body, headers = signed({ id: 'evt_1', type: 'physical_pos.payment.approved', data: { paymentId: 'p_1' } })
    error = assert_raises(Lunixi::WebhookError) { Lunixi::PhysicalPosWebhook.parse(body, headers, SECRET) }
    assert_match(/tolerance/, error.message) # the fixed test clock is far from now
    assert_raises(Lunixi::ConfigurationError) { Lunixi::PhysicalPosWebhook.parse(body, headers, nil) }
  end
end
