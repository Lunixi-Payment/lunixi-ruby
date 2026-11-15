# frozen_string_literal: true

require 'uri'

module Lunixi
  # Local checks of the payment-link image uploads: the create body, the bytes, the upload target the
  # gateway hands back and the confirmed image.
  module PaymentLinkImageRules
    FILE_NAME_MAX_LENGTH = 255
    UPLOAD_HEADER_NAME = /\A[A-Za-z0-9-]{1,64}\z/
    UPLOAD_HEADER_VALUE_MAX = 1024

    module_function

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

    private_class_method :upload_url?, :upload_headers?, :upload_header?
  end
end
