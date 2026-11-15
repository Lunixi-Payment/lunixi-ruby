# frozen_string_literal: true

require_relative 'test_helper'

class PaymentLinksTest < Minitest::Test
  ASSET_ID = '0f8fad5b-d9cb-469f-a165-70867728950e'
  UPLOAD_URL = 'https://storage.example/bucket/images/upload?X-Amz-Signature=synthetic'
  SVG = '<svg xmlns="http://www.w3.org/2000/svg"/>'
  PNG = "\x89PNG\r\n\x1A\n\x00\x00".b.freeze
  CREDENTIAL_HEADERS = %w[Authorization X-Key-Id X-Date X-Nonce X-Signature Digest Idempotency-Key].freeze

  def setup
    @target = { 'assetId' => ASSET_ID, 'uploadUrl' => UPLOAD_URL, 'uploadMethod' => 'PUT',
                'uploadHeaders' => { 'Content-Type' => 'image/png' }, 'expiresAt' => '2026-11-15T10:15:00Z' }
    @storage_status = 200
    @transport = RecordingTransport.new { |request| route(request) }
    @sdk = client(transport: @transport)
  end

  def route(request)
    return Lunixi::Response.new(status: @storage_status, headers: {}, body: storage_body) if request[:uri].host == 'storage.example'

    case request[:uri].path
    when %r{/qr\z} then Lunixi::Response.new(status: 200, headers: { 'content-type' => 'image/svg+xml' }, body: SVG.dup)
    when '/api/v1/payments/links/images' then response(201, { 'data' => @target })
    when %r{/confirm\z} then response(200, { 'data' => { 'assetId' => ASSET_ID, 'url' => nil, 'state' => 'PUBLISHED' } })
    else response(200, { 'data' => { 'id' => 'pl_1', 'rowVersion' => 3 } })
    end
  end

  def storage_body
    @storage_status == 200 ? '' : '<?xml version="1.0"?><Error><Code>AccessDenied</Code><Message>expired</Message></Error>'
  end

  def links
    @sdk.payment_links
  end

  def gateway_calls
    @transport.calls.reject { |request| request[:uri].path == '/api/v1/auth/token' }
  end

  def create_body
    { usage: Lunixi::PaymentLinkUsage::SINGLE_USE, amountMode: Lunixi::PaymentLinkAmountMode::FIXED, currency: 'TRY',
      amountMinor: '150000', title: 'Invoice 42', expiresAt: Time.utc(2026, 12, 1, 9) }
  end

  def assert_signed(request)
    assert request[:headers].key?('X-Signature'), "#{request[:method]} #{request[:uri].path} must be signed"
  end

  def test_create_is_signed_keyed_and_keeps_the_body_order
    links.create(create_body, idempotency_key: idempotency_key)
    sent = @transport.calls.last
    assert_equal ['POST', '/api/v1/payments/links'], [sent[:method], sent[:uri].path]
    assert_equal '{"usage":"SINGLE_USE","amountMode":"FIXED","currency":"TRY","amountMinor":"150000","title":"Invoice 42",' \
                 '"expiresAt":"2026-12-01T09:00:00.000Z"}', sent[:body]
    assert_equal idempotency_key, sent[:headers]['Idempotency-Key']
    assert_signed sent
  end

  def test_create_local_errors_send_nothing
    calls = gateway_calls.size
    assert_raises(Lunixi::ConfigurationError) { links.create(create_body) }
    assert_raises(Lunixi::ConfigurationError) { links.create(create_body.merge(price: '150000'), idempotency_key: idempotency_key) }
    assert_raises(Lunixi::ConfigurationError) { links.create(create_body.merge(amountMinor: 150_000), idempotency_key: idempotency_key) }
    assert_raises(Lunixi::ConfigurationError) { links.create(create_body.merge(expiresAt: 1_700_000_000), idempotency_key: idempotency_key) }
    assert_raises(Lunixi::ConfigurationError) { links.create([create_body], idempotency_key: idempotency_key) }
    assert_equal calls, gateway_calls.size
  end

  def test_update_sends_expected_row_version_first_and_refuses_fixed_fields
    links.update('pl_1', 3, { title: 'Invoice 42 (updated)', expiresAt: nil })
    sent = @transport.calls.last
    assert_equal ['PATCH', '/api/v1/payments/links/pl_1'], [sent[:method], sent[:uri].path]
    assert_equal '{"expectedRowVersion":3,"title":"Invoice 42 (updated)","expiresAt":null}', sent[:body]
    refute sent[:headers].key?('Idempotency-Key')
    assert_signed sent

    calls = gateway_calls.size
    [[3, {}], [3, { currency: 'USD' }], [3, { amountMode: 'OPEN' }], [3, { environment: 'LIVE' }], [3, { expectedRowVersion: 4 }],
     [-1, { title: 'x' }], ['3', { title: 'x' }]].each do |version, changes|
      assert_raises(Lunixi::ConfigurationError) { links.update('pl_1', version, changes) }
    end
    assert_raises(Lunixi::ConfigurationError) { links.update('pl/1', 3, { title: 'x' }) }
    assert_equal calls, gateway_calls.size
  end

  def test_pause_resume_deactivate_bodies
    links.pause('pl_1', expected_row_version: 3, reason: 'Out of stock', idempotency_key: idempotency_key)
    pause = @transport.calls.last
    assert_equal ['POST', '/api/v1/payments/links/pl_1/pause'], [pause[:method], pause[:uri].path]
    assert_equal '{"expectedRowVersion":3,"reason":"Out of stock"}', pause[:body]
    assert_equal idempotency_key, pause[:headers]['Idempotency-Key']
    links.resume('pl_1')
    assert_equal ['/api/v1/payments/links/pl_1/resume', '{}'], [@transport.calls.last[:uri].path, @transport.calls.last[:body]]
    links.deactivate('pl_1', reason: 'Closed')
    assert_equal '/api/v1/payments/links/pl_1/deactivate', @transport.calls.last[:uri].path
    gateway_calls.last(3).each { |request| assert_signed request }
    assert_raises(Lunixi::ConfigurationError) { links.action('pl_1', 'delete') }
  end

  def test_send_link_requires_a_key_and_a_known_channel
    links.send_link('pl_1', channel: Lunixi::PaymentLinkDeliveryChannel::EMAIL, recipient_email: 'buyer@example.com', locale: 'en',
                            idempotency_key: idempotency_key)
    sent = @transport.calls.last
    assert_equal '/api/v1/payments/links/pl_1/send', sent[:uri].path
    assert_equal '{"channel":"EMAIL","recipientEmail":"buyer@example.com","locale":"en"}', sent[:body]
    assert_signed sent

    calls = gateway_calls.size
    assert_raises(Lunixi::ConfigurationError) { links.send_link('pl_1', channel: 'EMAIL') }
    assert_raises(Lunixi::ConfigurationError) { links.send_link('pl_1', channel: 'FAX', idempotency_key: idempotency_key) }
    assert_raises(Lunixi::ConfigurationError) { links.send_link('pl_1', channel: 'SMS', locale: 'de', idempotency_key: idempotency_key) }
    assert_equal calls, gateway_calls.size
  end

  def test_qr_returns_image_bytes
    assert_equal SVG, links.qr('pl_1', size: 256)
    sent = @transport.calls.last
    assert_equal ['/api/v1/payments/links/pl_1/qr', 'format=svg&size=256'], [sent[:uri].path, sent[:uri].query]
    assert_equal 'image/svg+xml, image/png, application/json', sent[:headers]['Accept']
    assert_signed sent
    calls = gateway_calls.size
    assert_raises(Lunixi::ConfigurationError) { links.qr('pl_1', format: 'gif') }
    assert_raises(Lunixi::ConfigurationError) { links.qr('pl_1', size: 64) }
    assert_equal calls, gateway_calls.size
  end

  def test_lists_join_arrays_and_reject_unknown_filters
    links.list(state: %w[ACTIVE PAUSED], limit: 20, createdFrom: Time.utc(2026, 11, 1), includeTotal: true)
    list = @transport.calls.last
    assert_equal '/api/v1/payments/links', list[:uri].path
    assert_equal({ 'limit' => '20', 'includeTotal' => 'true', 'state' => 'ACTIVE,PAUSED', 'createdFrom' => '2026-11-01T00:00:00.000Z' },
                 URI.decode_www_form(list[:uri].query).to_h)
    links.list_attempts('pl_1', state: ['FAILED'])
    assert_equal ['/api/v1/payments/links/pl_1/attempts', 'state=FAILED'], [@transport.calls.last[:uri].path, @transport.calls.last[:uri].query]
    links.list_payments('pl_1', cursor: 'c_2')
    assert_equal ['/api/v1/payments/links/pl_1/payments', 'cursor=c_2'], [@transport.calls.last[:uri].path, @transport.calls.last[:uri].query]
    gateway_calls.last(3).each { |request| assert_signed request }
    assert_raises(Lunixi::ConfigurationError) { links.list(status: 'ACTIVE') }
    assert_raises(Lunixi::ConfigurationError) { links.list_payments('pl_1', state: 'SUCCEEDED') }
  end

  def test_upload_image_puts_only_the_upload_headers_to_storage
    image = links.upload_image(file_name: 'cover.png', content_type: Lunixi::PaymentLinkImageContentType::PNG, content: PNG)
    assert_equal 'PUBLISHED', image.dig('data', 'state')

    create, put, confirm = gateway_calls.last(3)
    assert_equal ['POST', '/api/v1/payments/links/images'], [create[:method], create[:uri].path]
    assert_equal %({"fileName":"cover.png","contentType":"image/png","sizeBytes":#{PNG.bytesize}}), create[:body]
    assert_signed create

    assert_equal ['PUT', UPLOAD_URL], [put[:method], put[:uri].to_s]
    assert_equal({ 'Content-Type' => 'image/png' }, put[:headers])
    CREDENTIAL_HEADERS.each { |name| refute put[:headers].key?(name), "#{name} must not reach the storage host" }
    assert_equal PNG, put[:body]

    assert_equal ['POST', "/api/v1/payments/links/images/#{ASSET_ID}/confirm", '{}'], [confirm[:method], confirm[:uri].path, confirm[:body]]
    assert_signed confirm
  end

  def test_unusable_upload_target_stops_before_the_put
    [{ 'uploadUrl' => 'http://storage.example/bucket/upload' }, { 'uploadMethod' => 'POST' }, { 'assetId' => 'asset_1' },
     { 'uploadHeaders' => { 'Content-Type' => "image/png\r\nAuthorization: x" } }, { 'uploadHeaders' => nil }].each do |change|
      @target = @target.merge(change)
      assert_raises(Lunixi::ApiError) { links.upload_image(file_name: 'cover.png', content_type: 'image/png', content: PNG) }
      @target = @target.merge('assetId' => ASSET_ID, 'uploadUrl' => UPLOAD_URL, 'uploadMethod' => 'PUT', 'uploadHeaders' => { 'Content-Type' => 'image/png' })
    end
    assert(@transport.calls.none? { |request| request[:uri].host == 'storage.example' })
  end

  def test_storage_failure_raises_with_the_storage_code_and_skips_confirm
    @storage_status = 403
    error = assert_raises(Lunixi::ApiError) { links.upload_image(file_name: 'cover.png', content_type: 'image/png', content: PNG) }
    assert_equal [403, 'AccessDenied'], [error.status, error.code]
    refute(@transport.calls.any? { |request| request[:uri].path.end_with?('/confirm') })
  end

  def test_image_upload_local_errors_send_nothing
    calls = gateway_calls.size
    assert_raises(Lunixi::ConfigurationError) { links.upload_image(file_name: 'cover.svg', content_type: 'image/svg+xml', content: SVG) }
    assert_raises(Lunixi::ConfigurationError) { links.upload_image(file_name: 'cover.png', content_type: 'image/png', content: '') }
    assert_raises(Lunixi::ConfigurationError) { links.create_image_upload(file_name: '', content_type: 'image/png', size_bytes: 10) }
    assert_raises(Lunixi::ConfigurationError) { links.create_image_upload(file_name: 'a.png', content_type: 'image/png', size_bytes: '10') }
    assert_raises(Lunixi::ConfigurationError) { links.create_image_upload(file_name: 'a.png', content_type: 'image/png', size_bytes: 0) }
    assert_raises(Lunixi::ConfigurationError) { links.confirm_image_upload('asset_1') }
    assert_equal calls, gateway_calls.size
  end
end
