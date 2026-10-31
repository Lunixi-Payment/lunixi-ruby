# frozen_string_literal: true

module Lunixi
  VerifiedEvent = Struct.new(:id, :type, :data, :raw, :body_digest, keyword_init: true)

  # Pure verification never consumes an event id. Use #process with a durable
  # transactional store so a crashed handler can safely receive the event again.
  class WebhookVerifier
    def initialize(secret:, previous_secrets: [], tolerance: 300, clock: -> { Time.now.utc })
      @secrets = [secret, *previous_secrets]
      unless @secrets.all? { |value| value.is_a?(String) && !value.empty? } && @secrets.size <= 3
        raise ConfigurationError, 'One webhook secret and at most two previous secrets are required'
      end

      @secrets = @secrets.map { |value| value.dup.freeze }.freeze
      raise ConfigurationError, 'Webhook tolerance must be between 1 and 3600 seconds' unless tolerance.is_a?(Integer) && tolerance.between?(1, 3600)

      @tolerance = tolerance
      @clock = clock
    end

    def verify(raw_body, headers)
      unless raw_body.is_a?(String) && raw_body.bytesize <= 1024 * 1024 && raw_body.dup.force_encoding('UTF-8').valid_encoding?
        raise WebhookError, 'Webhook body must be bounded UTF-8 bytes'
      end

      raw_body = raw_body.dup.freeze
      normalized = normalize_headers(headers)
      id, timestamp, signature = signature_fields(normalized)
      verify_signature(raw_body, id, timestamp, signature)
      envelope = JSON.parse(raw_body, max_nesting: 64, object_class: UniqueJsonObject, allow_duplicate_key: false)
      event_from_envelope(envelope, normalized, id, raw_body)
    rescue JSON::ParserError, ArgumentError
      raise WebhookError, 'Webhook data or timestamp is malformed', cause: nil
    end

    # The store must commit its receipt and all handler changes atomically. Its
    # process_once(id:, digest:) yields once, returns :processed or :duplicate,
    # and raises ReplayConflict when the same id has a different body digest.
    def process(raw_body, headers, store:)
      event = verify(raw_body, headers)
      store.process_once(id: event.id, digest: event.body_digest) { yield event }
    end

    def inspect
      '#<Lunixi::WebhookVerifier secrets=[REDACTED]>'
    end

    private

    def signature_fields(headers)
      id = headers['x-lunixi-event-id']
      timestamp = headers['x-lunixi-signature-timestamp']
      signature = headers['x-lunixi-signature']
      valid_id = id&.match?(/\A[a-zA-Z0-9_.:-]{1,200}\z/)
      valid_time = timestamp&.match?(/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,9})?(?:Z|[+-]\d\d:\d\d)\z/)
      raise WebhookError, 'Required webhook headers are missing or malformed' unless valid_id && valid_time && signature && signature.bytesize <= 2048
      raise WebhookError, 'Webhook timestamp is outside the tolerance window' if (@clock.call - Time.iso8601(timestamp)).abs > @tolerance

      [id, timestamp, signature]
    end

    def verify_signature(raw_body, id, timestamp, signature)
      candidates = signature.split(',').filter_map do |item|
        match = /\Av2=([a-fA-F0-9]{64})\z/.match(item.strip)
        match && match[1].downcase
      end
      raise WebhookError, 'Webhook requires a v2 signature' if candidates.empty? || candidates.size > 8

      signed = "#{id}.#{timestamp}.".b + raw_body.b
      matches = @secrets.flat_map do |secret|
        expected = OpenSSL::HMAC.hexdigest('SHA256', secret, signed)
        candidates.map { |candidate| OpenSSL.fixed_length_secure_compare(expected, candidate) }
      end
      raise WebhookError, 'Webhook signature is invalid' unless matches.include?(true)
    end

    def event_from_envelope(envelope, normalized, id, raw_body)
      raise WebhookError, 'Webhook envelope must be an object' unless envelope.is_a?(Hash)

      %w[id eventId].each do |field|
        raise WebhookError, 'Webhook event id does not match the signed header' if envelope.key?(field) && envelope[field] != id
      end
      type = event_type(envelope, normalized)
      data = envelope['data'] || envelope['payload'] || {}
      raise WebhookError, 'Webhook data must be an object' unless data.is_a?(Hash)

      VerifiedEvent.new(id: id.freeze, type: type.freeze, data: deep_freeze(data),
                        raw: deep_freeze(envelope), body_digest: Digest::SHA256.hexdigest(raw_body)).freeze
    end

    def event_type(envelope, normalized)
      types = %w[type eventType].filter_map { |field| envelope[field] }
      raise WebhookError, 'Webhook event type must be present in the signed body' if types.empty?

      header_type = normalized['x-lunixi-event-type']
      types << header_type if header_type
      unless !types.empty? && types.all? { |type| type.is_a?(String) && type.match?(/\A[a-zA-Z0-9_.:-]{1,200}\z/) } && types.uniq.one?
        raise WebhookError, 'Webhook event type is missing or inconsistent'
      end

      types.first
    end

    def normalize_headers(headers)
      raise WebhookError, 'Webhook headers must be a hash' unless headers.is_a?(Hash)

      headers.each_with_object({}) do |(name, value), result|
        key = name.to_s.downcase
        raise WebhookError, 'Duplicate or invalid webhook header' if result.key?(key) || !value.is_a?(String)

        result[key] = value.dup.freeze
      end
    end

    def deep_freeze(value)
      case value
      when Hash then value.each do |key, entry|
        key.freeze
        deep_freeze(entry)
      end
      when Array then value.each { |entry| deep_freeze(entry) }
      end
      value.freeze
    end
  end

  # JSON.parse otherwise silently overwrites duplicate keys, which can make two
  # applications interpret a signed JSON envelope differently.
  class UniqueJsonObject < Hash
    def []=(key, value)
      raise WebhookError, 'Webhook contains duplicate JSON keys' if key?(key)

      super
    end
  end
end
