# frozen_string_literal: true

require 'time'

module Lunixi
  # Local checks of the payment-link bodies (list filters: PaymentLinkFilters; image uploads:
  # PaymentLinkImageRules).
  module PaymentLinkRules
    CREATE_FIELDS = (['environment'] + PAYMENT_LINK_SPEC_FIELDS).freeze
    UPDATE_FIELDS = PAYMENT_LINK_SPEC_FIELDS
    TIME_FIELDS = %w[startsAt expiresAt eventAt].freeze
    LINK_ACTIONS = %w[pause resume deactivate].freeze
    QR_MIN_SIZE = 128
    QR_MAX_SIZE = 2048

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

    private_class_method :root!, :known!, :times, :time_value!, :iso8601
  end
end
