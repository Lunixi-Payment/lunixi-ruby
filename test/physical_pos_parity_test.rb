# frozen_string_literal: true

require_relative 'test_helper'

# test/fixtures/physical-pos-parity.json is byte-identical in the Node, PHP, Java, Python and Ruby SDKs.
# Its expected values come from the gateway rules (card-data key tokens, the guard's field paths, the
# PAN value scan) and the gateway DTOs (closed field and filter lists). A rule or list that drifts in
# one SDK turns this test red.
class PhysicalPosParityTest < Minitest::Test
  FIXTURE = JSON.parse(File.read(File.join(__dir__, 'fixtures', 'physical-pos-parity.json'), encoding: 'UTF-8'))
  KEY = 'pos-parity-key-0001'
  SALE = { 'operation' => 'SALE', 'target' => { 'deviceId' => '5f0c2b1e-1111-4222-8333-444455556666' },
           'amountMinor' => '4500', 'currency' => 'TRY' }.freeze

  def test_card_data_term_lists_match
    rule = FIXTURE.fetch('cardDataKeyRule')
    Lunixi::PhysicalPosCardData::KEY_RULE.each { |name, terms| assert_equal rule.fetch(name), terms, name }
    assert_equal rule.fetch('digitRunKeyPattern'), Lunixi::PhysicalPosCardData::DIGIT_RUN_KEY_SOURCE
  end

  def test_card_data_key_cases
    FIXTURE.fetch('cardDataKeyCases').each do |entry|
      assert_equal entry['cardData'], Lunixi::PhysicalPosCardData.card_data_key?(entry['key']), entry['key']
    end
  end

  def test_card_data_path_cases
    FIXTURE.fetch('cardDataPathCases').each do |entry|
      expected = entry['field']
      actual = Lunixi::PhysicalPosCardData.find_card_data_field(entry['body'])
      expected.nil? ? assert_nil(actual, entry['body'].inspect) : assert_equal(expected, actual, entry['body'].inspect)
    end
  end

  def test_pan_value_cases
    FIXTURE.fetch('panValueCases').each do |entry|
      actual = Lunixi::PhysicalPosCardNumber.contains_pan_like_value?(entry['value'], entry['mode'])
      assert_equal entry['pan'], actual, "#{entry['mode']}: #{entry['value']}"
    end
  end

  def test_idempotency_key_cases
    FIXTURE.fetch('idempotencyKeyCases').each do |entry|
      if entry['valid']
        assert_equal entry['key'], Lunixi::PhysicalPosIdentifiers.idempotency_key!(entry['key'])
      else
        assert_raises(Lunixi::ConfigurationError, entry['key'].inspect) { Lunixi::PhysicalPosIdentifiers.idempotency_key!(entry['key']) }
      end
    end
  end

  def test_valid_idempotency_keys_are_sent_unchanged
    keys = FIXTURE.fetch('idempotencyKeyCases').select { |entry| entry['valid'] }.map { |entry| entry['key'] }
    transport = RecordingTransport.new { response(202, accepted_payment) }
    pos = client(transport: transport).physical_pos
    keys.each { |key| pos.create_payment(SALE, idempotency_key: key) }
    sent = transport.calls.reject { |call| call[:uri].path == '/api/v1/auth/token' }.map { |call| call[:headers]['Idempotency-Key'] }
    assert_equal keys, sent
  end

  def test_forbidden_fields_are_refused_before_sending
    transport = RecordingTransport.new { response(202, accepted_payment) }
    pos = client(transport: transport).physical_pos
    FIXTURE.fetch('forbiddenFields').each do |field|
      assert_raises(Lunixi::ConfigurationError, Lunixi::PhysicalPosCardDataRejectedError, field) do
        pos.create_payment(SALE.merge(field => 'x'), idempotency_key: KEY)
      end
    end
    assert_empty transport.calls
  end

  def test_request_field_lists_match_the_gateway_dtos
    fields = FIXTURE.fetch('requestFields')
    assert_equal fields.fetch('paymentTarget'), Lunixi::PHYSICAL_POS_PAYMENT_TARGET_FIELDS
    assert_equal fields.fetch('saleItem'), Lunixi::PHYSICAL_POS_SALE_ITEM_FIELDS
    assert_equal fields.fetch('refundItem'), Lunixi::PHYSICAL_POS_REFUND_ITEM_FIELDS
    assert_equal fields.fetch('saleItem'), Lunixi::PhysicalPosRequest::SALE_ITEM_KINDS.keys
    assert_equal fields.fetch('refundItem'), Lunixi::PhysicalPosRequest::REFUND_ITEM_KINDS.keys
    assert_equal fields.fetch('paymentTarget'), Lunixi::PhysicalPosRequest::TARGET_KINDS.keys
    request_fields = Lunixi::PHYSICAL_POS_REQUEST_FIELDS
    assert_equal fields.keys.sort - %w[paymentTarget saleItem refundItem], request_fields.keys.sort
    request_fields.each { |operation, kinds| assert_equal fields.fetch(operation), kinds.keys, operation }
  end

  def test_filter_lists_match_the_gateway_dtos
    expected = FIXTURE.fetch('filters')
    assert_equal expected.keys.sort, Lunixi::PHYSICAL_POS_FILTERS.keys.sort
    Lunixi::PHYSICAL_POS_FILTERS.each { |route, names| assert_equal expected.fetch(route).sort, names.sort, route }
  end

  def test_event_types_match
    assert_equal FIXTURE.fetch('eventTypes'), Lunixi::PHYSICAL_POS_EVENT_TYPES
    assert_equal 'physical_pos.*', Lunixi::PhysicalPosEvents::ALL_EVENTS
  end

  def test_webhook_original_cases
    FIXTURE.fetch('webhookOriginalCases').each do |entry|
      actual = Lunixi::PhysicalPosWebhook.original(entry['data'])
      entry['original'].nil? ? assert_nil(actual, entry['name']) : assert_equal(entry['original'], actual, entry['name'])
    end
  end

  def test_webhook_cashier_cases
    FIXTURE.fetch('webhookCashierCases').each do |entry|
      actual = Lunixi::PhysicalPosWebhook.cashier(entry['data'])
      entry['cashier'].nil? ? assert_nil(actual, entry['name']) : assert_equal(entry['cashier'], actual, entry['name'])
    end
  end

  def test_webhook_category_cases
    FIXTURE.fetch('webhookCategoryCases').each do |entry|
      assert_equal entry['category'], Lunixi::PhysicalPosWebhook.category(entry['type']), entry['type']
    end
  end

  def test_not_started_codes_match
    assert_equal FIXTURE.fetch('notStartedCodes'), Lunixi::PHYSICAL_POS_NOT_STARTED_CODES
  end

  # A valid id is percent-encoded (a/b → a%2Fb). Client#request then refuses a segment that decodes to
  # a slash, so such an id still never reaches the gateway.
  def test_path_id_cases
    FIXTURE.fetch('pathIdCases').each do |entry|
      if entry['valid']
        assert_equal entry.fetch('encoded', entry['id']), Lunixi::PhysicalPosIdentifiers.path_id(entry['id'], 'paymentId')
      else
        assert_raises(Lunixi::ConfigurationError, entry['id'].inspect) { Lunixi::PhysicalPosIdentifiers.path_id(entry['id'], 'paymentId') }
      end
    end
  end

  private

  def accepted_payment
    { 'data' => { 'payment' => { 'paymentId' => 'p_1', 'paymentStatus' => 'NOT_STARTED' }, 'replayed' => false }, 'statusCode' => 202 }
  end
end
