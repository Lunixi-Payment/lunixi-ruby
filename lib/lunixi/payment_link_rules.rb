# frozen_string_literal: true

require 'time'
require 'uri'

module Lunixi
  # Local checks of the payment-link bodies, filters and image upload targets.
  module PaymentLinkRules
    CREATE_FIELDS = (['environment'] + PAYMENT_LINK_SPEC_FIELDS).freeze
    UPDATE_FIELDS = PAYMENT_LINK_SPEC_FIELDS
    TIME_FIELDS = %w[startsAt expiresAt eventAt].freeze
    LINK_LIST_FILTERS = %w[limit cursor includeTotal state usage amountMode environment tag branchCode createdById query
                           createdFrom createdTo].freeze
    ATTEMPT_LIST_FILTERS = %w[limit cursor includeTotal state].freeze
    PAYMENT_LIST_FILTERS = %w[limit cursor includeTotal].freeze
    LINK_ACTIONS = %w[pause resume deactivate].freeze
    QR_MIN_SIZE = 128
    QR_MAX_SIZE = 2048
    FILE_NAME_MAX_LENGTH = 255
    UPLOAD_HEADER_NAME = /\A[A-Za-z0-9-]{1,64}\z/
    UPLOAD_HEADER_VALUE_MAX = 1024

    module_function

    def create_body!(body)
      data = root!(body, 'Payment link request')
      known!(data, CREATE_FIELDS, 'create')
      times(data)
    end

    # Only the given keys are updated; nil clears a field.
    def update_body!(changes)
      data = root!(changes, 'Payment link changes')
      raise ConfigurationError, 'Payment link update needs at least one changed field' if data.empty?

      fixed = data.keys.find { |key| PAYMENT_LINK_IMMUTABLE_FIELDS.include?(key) }
      raise ConfigurationError, "'#{fixed}' is fixed when a payment link is created and cannot be updated; create a new link instead" if fixed

      known!(data, UPDATE_FIELDS, 'update')
      times(data)
    end

    # pause / resume / deactivate body: expectedRowVersion (optional) and reason.
    def action_body!(action, expected_row_version, reason)
      raise ConfigurationError, "Payment link action must be one of #{LINK_ACTIONS.join(', ')}" unless LINK_ACTIONS.include?(action.to_s)

      body = {}
      body['expectedRowVersion'] = row_version!(expected_row_version) unless expected_row_version.nil?
      body['reason'] = reason.to_s unless reason.nil?
      body
    end

    def send_body!(channel, recipient_email, recipient_phone, locale)
      unless PaymentLinkDeliveryChannel::ALL.include?(channel)
        raise ConfigurationError, "Send channel must be one of #{PaymentLinkDeliveryChannel::ALL.join(', ')}"
      end

      body = { 'channel' => channel }
      body['recipientEmail'] = recipient_email.to_s unless recipient_email.nil?
      body['recipientPhone'] = recipient_phone.to_s unless recipient_phone.nil?
      unless locale.nil?
        raise ConfigurationError, "Send locale must be one of #{PaymentLinkLocale::ALL.join(', ')}" unless PaymentLinkLocale::ALL.include?(locale)

        body['locale'] = locale
      end
      body
    end

    def qr_query!(format, size)
      raise ConfigurationError, "QR format must be one of #{PaymentLinkQrFormat::ALL.join(', ')}" unless PaymentLinkQrFormat::ALL.include?(format)

      query = { 'format' => format }
      return query if size.nil?
      unless size.is_a?(Integer) && size.between?(QR_MIN_SIZE, QR_MAX_SIZE)
        raise ConfigurationError, "QR size must be an integer in pixels, #{QR_MIN_SIZE}-#{QR_MAX_SIZE}"
      end

      query.merge('size' => size)
    end

    # Lists accept an Array for state, usage and amountMode (sent as a comma list) and a Time for the
    # createdFrom / createdTo window.
    def list_query!(filters, allowed, operation)
      data = filters.transform_keys(&:to_s)
      unknown = data.keys - allowed
      raise ConfigurationError, "#{operation} does not take #{unknown.join(', ')}; filters: #{allowed.join(', ')}" unless unknown.empty?

      allowed.each_with_object({}) do |key, query|
        value = data[key]
        next if value.nil? || value == ''

        value = value.join(',') if value.is_a?(Array)
        value = iso8601(value) if value.is_a?(Time)
        query[key] = value unless value == ''
      end
    end

    def row_version!(value)
      unless value.is_a?(Integer) && value.between?(0, JsonBody::MAX_SAFE_INTEGER)
        raise ConfigurationError, "expectedRowVersion must be the link's current rowVersion (a nonnegative integer)"
      end

      value
    end

    def link_id!(value)
      raise ConfigurationError, 'link_id is required' unless value.is_a?(String) && value.match?(/\A[a-zA-Z0-9_-]{1,256}\z/)

      value
    end

    def asset_id!(value)
      raise ConfigurationError, "asset_id must be the image's asset id (UUID)" unless value.is_a?(String) && value.match?(PAYMENT_LINK_ASSET_ID_PATTERN)

      value
    end

    def image_body!(file_name, content_type, size_bytes)
      unless file_name.is_a?(String) && !file_name.strip.empty? && file_name.length <= FILE_NAME_MAX_LENGTH
        raise ConfigurationError, "file_name must be 1–#{FILE_NAME_MAX_LENGTH} characters"
      end
      unless PaymentLinkImageContentType::ALL.include?(content_type)
        raise ConfigurationError, "Image content_type must be one of #{PaymentLinkImageContentType::ALL.join(', ')} (SVG is not accepted)"
      end
      unless size_bytes.is_a?(Integer) && size_bytes.between?(1, JsonBody::MAX_SAFE_INTEGER)
        raise ConfigurationError, 'Image size_bytes must be the file size in bytes (a positive integer)'
      end

      { 'fileName' => file_name, 'contentType' => content_type, 'sizeBytes' => size_bytes }
    end

    def image_content!(content)
      raise ConfigurationError, 'Image content must be a nonempty binary String' unless content.is_a?(String) && !content.empty?

      content.b
    end

    # An upload target is used only if the SDK can PUT to it as documented: an asset id, an HTTPS URL
    # without credentials, the PUT method and string headers. Anything else fails before a byte is sent.
    def upload_target!(envelope)
      target = envelope.is_a?(Hash) ? envelope['data'] : nil
      usable = target.is_a?(Hash) && target['assetId'].is_a?(String) && target['assetId'].match?(PAYMENT_LINK_ASSET_ID_PATTERN) &&
               upload_url?(target['uploadUrl']) && target['uploadMethod'] == 'PUT' && upload_headers?(target['uploadHeaders'])
      raise ApiError.new(status: 502, code: 'invalid_image_upload_target') unless usable

      target
    end

    def published_image!(envelope)
      image = envelope.is_a?(Hash) ? envelope['data'] : nil
      return if image.is_a?(Hash) && image['assetId'].is_a?(String) && image['state'] == 'PUBLISHED'

      raise ApiError.new(status: 502, code: 'image_not_published')
    end

    # S3-compatible storage answers errors as XML: <Error><Code>AccessDenied</Code>…
    def storage_error_code(body)
      match = body.to_s.b.match(%r{<Code>([A-Za-z0-9.]{1,64})</Code>})
      match && match[1]
    end

    def upload_url?(value)
      uri = URI.parse(value)
      uri.is_a?(URI::HTTPS) && !uri.host.to_s.empty? && uri.userinfo.nil? && uri.fragment.nil? && value.bytesize <= 8192
    rescue URI::InvalidURIError, TypeError
      false
    end

    def upload_headers?(headers)
      return false unless headers.is_a?(Hash) && headers.size <= 32

      headers.all? { |name, value| upload_header?(name, value) }
    end

    def upload_header?(name, value)
      name.is_a?(String) && name.match?(UPLOAD_HEADER_NAME) && value.is_a?(String) &&
        value.bytesize <= UPLOAD_HEADER_VALUE_MAX && !value.match?(/[\x00-\x1f\x7f]/)
    end

    def root!(body, name)
      raise ConfigurationError, "#{name} must be an object" unless body.is_a?(Hash)

      body.each_with_object({}) do |(key, value), data|
        raise ConfigurationError, "#{name} keys must be strings or symbols" unless key.is_a?(String) || key.is_a?(Symbol)
        raise ConfigurationError, "#{name} repeats the key #{key}" if data.key?(key.to_s)

        data[key.to_s] = value
      end
    end

    def known!(data, allowed, operation)
      unknown = data.keys - allowed
      return if unknown.empty?

      raise ConfigurationError, "Unknown payment link #{operation} field(s): #{unknown.join(', ')}; the gateway rejects unknown fields with 400"
    end

    # A Time is sent as ISO 8601 (UTC, milliseconds); a String as given; nil clears the value.
    def times(data)
      TIME_FIELDS.each do |key|
        next unless data.key?(key)

        value = data[key]
        next if value.nil?

        data[key] = time_value!(value, key)
      end
      data
    end

    def time_value!(value, key)
      return iso8601(value) if value.is_a?(Time)
      return value if value.is_a?(String) && !value.strip.empty?

      raise ConfigurationError, "#{key} must be a Time, an ISO 8601 string or nil"
    end

    def iso8601(time)
      time.getutc.iso8601(3)
    end

    private_class_method :upload_url?, :upload_headers?, :upload_header?, :root!, :known!, :times, :time_value!, :iso8601
  end
end
