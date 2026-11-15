# frozen_string_literal: true

require 'securerandom'

module Lunixi
  # Local checks shared by PhysicalPos and PhysicalPosManagement: field lists, card data (field names
  # and card-number values), the Idempotency-Key and path identifiers. Filters are checked by
  # PhysicalPosFilters; answers and errors are read by PhysicalPosResponses.
  # Shape and canonical money are checked here; value rules (operation set, ranges, item totals, target
  # uniqueness) stay on the gateway, which answers with a typed physical_pos.* code.
  module PhysicalPosRequest
    BASE = '/api/v1/physical-pos'
    ROUTE = %r{\A/api/v1/physical-pos(?:[/?]|\z)}
    MAX_SAFE_INTEGER = JsonBody::MAX_SAFE_INTEGER
    # A field check's answer for "leave the field out" (nil is a real value: an explicit clear).
    OMIT = Object.new.freeze
    SALE_ITEM_KINDS = {
      'lineNo' => 'int*', 'name' => 'string*', 'quantityMilli' => 'int*', 'unitCode' => 'string*', 'unitPriceMinor' => 'money*',
      'taxGroupCode' => 'string*', 'lineTotalMinor' => 'money*', 'barcode' => 'string'
    }.freeze
    REFUND_ITEM_KINDS = { 'lineNo' => 'int*', 'quantityMilli' => 'int*', 'amountMinor' => 'money' }.freeze
    TARGET_KINDS = PHYSICAL_POS_PAYMENT_TARGET_FIELDS.to_h { |name| [name, 'string'] }.freeze
    CARD_DATA_MESSAGE = 'Physical POS requests must not contain card data: the card is read on the device. Remove the field ' \
                        'or value; do not send card numbers, expiry dates or security codes.'

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
      integer!(value, field)
      unless value.between?(1, PHYSICAL_POS_ROW_VERSION_MAX)
        raise ConfigurationError, "'#{field}' must be between 1 and #{PHYSICAL_POS_ROW_VERSION_MAX}: send the rowVersion you last read."
      end

      value
    end

    # ── Bodies ───────────────────────────────────────────────────────────────

    # Builds a request body from a field list (PHYSICAL_POS_REQUEST_FIELDS): card-data keys first
    # (PhysicalPosCardDataRejectedError), then unknown fields, required fields and value types
    # (ConfigurationError), then card-number values in the scanned free-text fields. Keys are the wire
    # names (String or Symbol); snake_case names are accepted too. Nothing is sent when a check fails.
    def body!(request, kinds, label)
      reject_card_data!(request, '(body)') unless request.nil?
      given = wire_keys!(request, kinds.keys, label)
      body = {}
      kinds.each do |key, kind|
        unless given.key?(key)
          raise ConfigurationError, "'#{key}' is required." if kind.end_with?('*')

          next
        end
        checked = check_value(kind, given[key], key)
        body[key] = checked unless checked.equal?(OMIT)
      end
      reject_card_numbers!(body)
      body
    end

    # One value against its kind. Money is a canonical string; present nil or blank money is refused.
    # nil is sent only for a nullable (?) field and left out for any other optional field; '' is left
    # out for an optional string and refused for a required one.
    def check_value(kind_spec, value, field)
      required = kind_spec.end_with?('*')
      nullable = kind_spec.end_with?('?')
      kind = kind_spec.delete_suffix('*').delete_suffix('?')
      return money!(value, field) if kind == 'money'
      return nil_value(required, nullable, field) if value.nil?
      return OMIT if value == '' && !required

      case kind
      when 'string' then string!(value, field)
      when 'int' then integer!(value, field)
      when 'rowVersion' then row_version!(value, field)
      when 'bool' then boolean!(value, field)
      when 'strings' then strings!(value, field)
      when 'target' then object_of(value, TARGET_KINDS, field)
      when 'saleItems' then items_of(value, SALE_ITEM_KINDS, field)
      when 'refundItems' then items_of(value, REFUND_ITEM_KINDS, field)
      else raise ConfigurationError, "Unsupported field kind '#{kind_spec}'."
      end
    end

    def nil_value(required, nullable, field)
      return nil if nullable
      raise ConfigurationError, "'#{field}' is required." if required

      OMIT
    end

    def object_of(value, kinds, field)
      given = wire_keys!(value, kinds.keys, "'#{field}'")
      kinds.each_with_object({}) do |(key, kind), out|
        next unless given.key?(key)

        checked = check_value(kind, given[key], "#{field}.#{key}")
        out[key] = checked unless checked.equal?(OMIT)
      end
    end

    def items_of(value, kinds, field)
      unless value.is_a?(Array) && !value.empty?
        raise ConfigurationError, "'#{field}' must be a non-empty array; leave the field out for a request without items."
      end

      value.each_with_index.map do |item, index|
        path = "#{field}[#{index}]"
        out = object_of(item, kinds, path)
        kinds.each { |key, kind| raise ConfigurationError, "'#{path}.#{key}' is required." if kind.end_with?('*') && !out.key?(key) }
        out
      end
    end

    def string!(value, field)
      raise ConfigurationError, "'#{field}' must be a non-empty string." unless value.is_a?(String) && !value.empty?

      value
    end

    def integer!(value, field)
      unless value.is_a?(Integer) && value.abs <= MAX_SAFE_INTEGER
        raise ConfigurationError, "'#{field}' must be an integer (a JSON number, not a string)."
      end

      value
    end

    def boolean!(value, field)
      raise ConfigurationError, "'#{field}' must be a boolean." unless [true, false].include?(value)

      value
    end

    def strings!(value, field)
      unless value.is_a?(Array) && value.all? { |entry| entry.is_a?(String) && !entry.empty? }
        raise ConfigurationError, "'#{field}' must be an array of non-empty strings."
      end

      value.dup
    end

    def money!(value, field)
      Money.minor(value, positive: true)
    rescue ConfigurationError
      raise ConfigurationError, "'#{field}' must be a canonical minor-unit string such as \"4500\" (not a number).", cause: nil
    end

    # Wire names of a body or filter set: String or Symbol keys, the wire name or its snake_case form.
    def wire_keys!(value, allowed, label, kind = 'field')
      raise ConfigurationError, "#{label} must be a Hash." unless value.is_a?(Hash)

      unknown = []
      given = value.each_with_object({}) do |(key, entry), out|
        raise ConfigurationError, "#{label} keys must be strings or symbols." unless key.is_a?(String) || key.is_a?(Symbol)

        name = key.to_s
        wire = allowed.include?(name) ? name : camel(name)
        next unknown << name unless allowed.include?(wire)
        raise ConfigurationError, "#{label} #{kind} '#{wire}' is given twice." if out.key?(wire)

        out[wire] = entry
      end
      return given if unknown.empty?

      raise ConfigurationError, "Unknown #{label} #{kind}(s): #{unknown.join(', ')}. Allowed: #{allowed.join(', ')}. " \
                                'The gateway rejects unknown fields with 400.'
    end

    def camel(name)
      name.gsub(/_([a-z0-9])/) { Regexp.last_match(1).upcase }
    end

    # ── Card data ────────────────────────────────────────────────────────────

    def card_data_rejected(field)
      PhysicalPosCardDataRejectedError.new(status: 0, field: field, message: "#{CARD_DATA_MESSAGE} Field: #{field}.")
    end

    def reject_card_data!(value, root)
      field = PhysicalPosCardData.find_card_data_field(value, root)
      raise card_data_rejected(field) unless field.nil?
    end

    # Card-number values in the free-text fields the gateway scans (the value never reaches the error).
    def reject_card_numbers!(body)
      raise card_data_rejected('merchantReference') if PhysicalPosCardData.contains_pan_like_value?(body['merchantReference'])

      Array(body['items']).each_with_index do |item, index|
        raise card_data_rejected("items[#{index}].name") if PhysicalPosCardData.contains_pan_like_value?(item['name'], PhysicalPosCardData::ITEM_TEXT)
        raise card_data_rejected("items[#{index}].taxGroupCode") if PhysicalPosCardData.contains_pan_like_value?(item['taxGroupCode'])
      end
    end
  end
end
