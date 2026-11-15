# frozen_string_literal: true

module Lunixi
  # Payment links (/api/v1/payments/links). Every gateway call here is signed, reads included: the
  # merchant and the environment come from the signing key, so a TEST key sees and changes only TEST
  # links. The key needs the matching scope (payment-link:create, :view, :manage, :send).
  #
  # Responses are the gateway envelope. Lists carry data.items and the top-level pageInfo
  # (hasMore, nextCursor, totalCount); pass pageInfo.nextCursor as cursor for the next page.
  #
  # The one request that is not sent to the gateway is the image PUT of upload_image: it goes to the
  # storage host behind a presigned URL with only the uploadHeaders, never with the access token or the
  # request signature.
  class PaymentLinks
    BASE = '/api/v1/payments/links'
    IMAGES = "#{BASE}/images".freeze
    QR_ACCEPT = 'image/svg+xml, image/png, application/json'
    attr_reader :client

    def initialize(client, storage_transport:)
      @client = client
      @storage_transport = storage_transport
    end

    # Create a link. The idempotency key is required: the same key with the same body returns the stored
    # link with replayed: true; the same key with another body is 409 payment_link.idempotency.conflict.
    # Only PAYMENT_LINK_SPEC_FIELDS and environment are accepted; amounts are minor-unit strings.
    def create(body, idempotency_key: nil)
      client.request('POST', BASE, body: PaymentLinkRules.create_body!(body), idempotency_key: Client.idempotency_key!(idempotency_key))
    end

    # One page of links, newest first. state, usage and amountMode take an Array; createdFrom /
    # createdTo (a Time or ISO 8601 string) bound a half-open window; query matches a short code or a
    # title/reference prefix.
    def list(**filters)
      client.request('GET', BASE, query: PaymentLinkFilters.list_query!(filters, PaymentLinkFilters::LINK_LIST_FILTERS, 'payment_links.list'))
    end

    def get(link_id)
      client.request('GET', link_path(link_id))
    end

    # Change a link (a new version of it). expected_row_version is the link's current rowVersion; a
    # concurrent change is 409 payment_link.link.version_conflict. Only the given keys change, nil clears
    # a field and a nested object is replaced whole. usage, amountMode and currency are fixed.
    def update(link_id, expected_row_version, changes, idempotency_key: nil)
      body = { 'expectedRowVersion' => PaymentLinkRules.row_version!(expected_row_version) }.merge(PaymentLinkRules.update_body!(changes))
      client.request('PATCH', link_path(link_id), body: body, idempotency_key: optional_key(idempotency_key))
    end

    # Stop accepting payments until resume.
    def pause(link_id, expected_row_version: nil, reason: nil, idempotency_key: nil)
      action(link_id, 'pause', expected_row_version: expected_row_version, reason: reason, idempotency_key: idempotency_key)
    end

    def resume(link_id, expected_row_version: nil, reason: nil, idempotency_key: nil)
      action(link_id, 'resume', expected_row_version: expected_row_version, reason: reason, idempotency_key: idempotency_key)
    end

    # Close the link permanently; it cannot be reopened.
    def deactivate(link_id, expected_row_version: nil, reason: nil, idempotency_key: nil)
      action(link_id, 'deactivate', expected_row_version: expected_row_version, reason: reason, idempotency_key: idempotency_key)
    end

    # pause, resume or deactivate. Without expected_row_version there is no version check.
    def action(link_id, action, expected_row_version: nil, reason: nil, idempotency_key: nil)
      body = PaymentLinkRules.action_body!(action, expected_row_version, reason)
      client.request('POST', "#{link_path(link_id)}/#{action}", body: body, idempotency_key: optional_key(idempotency_key))
    end

    # Send the link by e-mail or SMS (PaymentLinkDeliveryChannel); without a recipient the link's
    # recipient is used. The idempotency key is required so a retry cannot send twice. An accepted
    # delivery can still fail: read data.delivery.state and failureReason.
    def send_link(link_id, channel: nil, recipient_email: nil, recipient_phone: nil, locale: nil, idempotency_key: nil)
      body = PaymentLinkRules.send_body!(channel, recipient_email, recipient_phone, locale)
      client.request('POST', "#{link_path(link_id)}/send", body: body, idempotency_key: Client.idempotency_key!(idempotency_key))
    end

    # The link's QR code as frozen image bytes (SVG or PNG, PaymentLinkQrFormat); size is 128–2048 px.
    def qr(link_id, format: PaymentLinkQrFormat::SVG, size: nil)
      client.request('GET', "#{link_path(link_id)}/qr", query: PaymentLinkRules.qr_query!(format, size), binary: true, accept: QR_ACCEPT)
    end

    # Payment attempts on the link, newest first; state takes an Array.
    def list_attempts(link_id, **filters)
      query = PaymentLinkFilters.list_query!(filters, PaymentLinkFilters::ATTEMPT_LIST_FILTERS, 'payment_links.list_attempts')
      client.request('GET', "#{link_path(link_id)}/attempts", query: query)
    end

    # Successful payments on the link, with refund totals.
    def list_payments(link_id, **filters)
      query = PaymentLinkFilters.list_query!(filters, PaymentLinkFilters::PAYMENT_LIST_FILTERS, 'payment_links.list_payments')
      client.request('GET', "#{link_path(link_id)}/payments", query: query)
    end

    # Link image, step 1 of 3: an upload target for a PNG, JPEG or WebP image. data is { assetId,
    # uploadUrl, uploadMethod: 'PUT', uploadHeaders, expiresAt }. Step 2 is a PUT of the bytes to
    # uploadUrl with exactly uploadHeaders before expiresAt; step 3 is confirm_image_upload(assetId).
    # A declared size over the image limit (2 MiB) is refused by the gateway before anything is uploaded.
    def create_image_upload(file_name: nil, content_type: nil, size_bytes: nil)
      body = PaymentLinkImageRules.image_body!(file_name, content_type, size_bytes)
      envelope = client.request('POST', IMAGES, body: body)
      PaymentLinkImageRules.upload_target!(envelope)
      envelope
    end

    # Link image, step 3 of 3: publish the uploaded image. data is { assetId, url, state: 'PUBLISHED' };
    # use assetId as the imageAssetId of a link or an item. Confirming before the PUT has landed is
    # 400 media.confirm.object_missing and can be retried.
    def confirm_image_upload(asset_id)
      envelope = client.request('POST', "#{IMAGES}/#{PaymentLinkImageRules.asset_id!(asset_id)}/confirm", body: {})
      PaymentLinkImageRules.published_image!(envelope)
      envelope
    end

    # Upload a link image in one call: create_image_upload, the PUT of content to the storage host and
    # confirm_image_upload. A failed PUT is not retried; it raises ApiError with the storage status (and
    # its error code, e.g. AccessDenied once the URL has expired). Call upload_image again for a new URL.
    def upload_image(file_name: nil, content_type: nil, content: nil)
      bytes = PaymentLinkImageRules.image_content!(content)
      target = PaymentLinkImageRules.upload_target!(create_image_upload(file_name: file_name, content_type: content_type, size_bytes: bytes.bytesize))
      put_to_storage(target, bytes)
      confirm_image_upload(target['assetId'])
    end

    def inspect
      '#<Lunixi::PaymentLinks>'
    end

    private

    # The PUT deliberately does not use Client#request: that adds the bearer token and the signature
    # headers, which must never reach the storage host. Only the headers the URL was signed for are sent.
    def put_to_storage(target, bytes)
      response = @storage_transport.call(method: 'PUT', uri: URI.parse(target['uploadUrl']), headers: target['uploadHeaders'].dup.freeze, body: bytes)
      raise TransportError, 'Image upload to storage returned an invalid response' unless response.is_a?(Response) && response.status.is_a?(Integer)
      return if response.status.between?(200, 299)

      raise ApiError.new(status: response.status, code: PaymentLinkImageRules.storage_error_code(response.body))
    rescue TransportError
      raise TransportError, 'Image upload to storage failed; call upload_image again for a new upload URL', cause: nil
    end

    def link_path(link_id)
      "#{BASE}/#{PaymentLinkRules.link_id!(link_id)}"
    end

    def optional_key(key)
      key.nil? ? nil : Client.idempotency_key!(key)
    end
  end
end
