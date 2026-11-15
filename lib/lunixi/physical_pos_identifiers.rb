# frozen_string_literal: true

require 'securerandom'

module Lunixi
  # The Idempotency-Key and the path identifiers of the physical POS requests. Not a public API.
  module PhysicalPosIdentifiers
    module_function

    # ── Idempotency-Key ──────────────────────────────────────────────────────

    # A new Idempotency-Key (UUID v4). Store it with your order before you call.
    def new_idempotency_key
      SecureRandom.uuid
    end

    # A key you pass is checked and sent exactly as given (never trimmed).
    def idempotency_key!(key)
      unless key.is_a?(String) && key.match?(PHYSICAL_POS_IDEMPOTENCY_KEY_PATTERN)
        raise ConfigurationError, 'The Idempotency-Key must be 8–200 printable ASCII characters without spaces; it is sent exactly ' \
                                  'as given. Use a new UUID for every operation and the same key to retry it.'
      end

      key
    end

    # The key to send where the SDK may create one: the caller's key (checked) or a new UUID for nil.
    def idempotency_key_or_new(key)
      key.nil? ? new_idempotency_key : idempotency_key!(key)
    end

    # Payment start and reversal: the caller must pass the key (nothing is generated).
    def required_idempotency_key!(key, operation)
      if key.nil?
        raise ConfigurationError, "A stable idempotency_key is required for #{operation}. Create one with " \
                                  'Lunixi::PhysicalPos.new_idempotency_key, store it with your order, then call; when the outcome ' \
                                  'is unknown call again with the SAME key.'
      end

      idempotency_key!(key)
    end

    # ── Identifiers ──────────────────────────────────────────────────────────

    # A path segment: a non-empty String, not . or .., percent-encoded (everything but A-Z a-z 0-9 - _ . ~).
    def path_id(value, field)
      raise ConfigurationError, "'#{field}' must be a non-empty string." unless value.is_a?(String) && !value.empty?
      raise ConfigurationError, "'#{field}' is not a valid identifier." if ['.', '..'].include?(value)

      value.b.gsub(/[^A-Za-z0-9_.~-]/n) { |byte| format('%%%02X', byte.ord) }.force_encoding(Encoding::UTF_8)
    end

    def row_version!(value, field)
      PhysicalPosValue.integer!(value, field)
      unless value.between?(1, PHYSICAL_POS_ROW_VERSION_MAX)
        raise ConfigurationError, "'#{field}' must be between 1 and #{PHYSICAL_POS_ROW_VERSION_MAX}: send the rowVersion you last read."
      end

      value
    end
  end
end
