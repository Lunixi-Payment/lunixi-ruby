# frozen_string_literal: true

module Lunixi
  # Local checks shared by PhysicalPos and PhysicalPosManagement: field lists and value kinds. Single
  # values are checked by PhysicalPosValue, card data is refused by PhysicalPosCardData, the
  # Idempotency-Key and path identifiers are checked by PhysicalPosIdentifiers and filters by
  # PhysicalPosFilters; answers and errors are read by PhysicalPosResponses.
  # Shape and canonical money are checked here; value rules (operation set, ranges, item totals, target
  # uniqueness) stay on the gateway, which answers with a typed physical_pos.* code.
  module PhysicalPosRequest
    BASE = '/api/v1/physical-pos'
    ROUTE = %r{\A/api/v1/physical-pos(?:[/?]|\z)}
    # A field check's answer for "leave the field out" (nil is a real value: an explicit clear).
    OMIT = Object.new.freeze
    SALE_ITEM_KINDS = {
      'lineNo' => 'int*', 'name' => 'string*', 'quantityMilli' => 'int*', 'unitCode' => 'string*', 'unitPriceMinor' => 'money*',
      'taxGroupCode' => 'string*', 'lineTotalMinor' => 'money*', 'barcode' => 'string'
    }.freeze
    REFUND_ITEM_KINDS = { 'lineNo' => 'int*', 'quantityMilli' => 'int*', 'amountMinor' => 'money' }.freeze
    TARGET_KINDS = PHYSICAL_POS_PAYMENT_TARGET_FIELDS.to_h { |name| [name, 'string'] }.freeze

    module_function

    # ── Bodies ───────────────────────────────────────────────────────────────

    # Builds a request body from a field list (PHYSICAL_POS_REQUEST_FIELDS): card-data keys first
    # (PhysicalPosCardDataRejectedError), then unknown fields, required fields and value types
    # (ConfigurationError), then card-number values in the scanned free-text fields. Keys are the wire
    # names (String or Symbol); snake_case names are accepted too. Nothing is sent when a check fails.
    def body!(request, kinds, label)
      PhysicalPosCardData.reject_card_data!(request, '(body)') unless request.nil?
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
      PhysicalPosCardData.reject_card_numbers!(body)
      body
    end

    # One value against its kind. Money is a canonical string; present nil or blank money is refused.
    # nil is sent only for a nullable (?) field and left out for any other optional field; '' is left
    # out for an optional string and refused for a required one.
    def check_value(kind_spec, value, field)
      required = kind_spec.end_with?('*')
      nullable = kind_spec.end_with?('?')
      kind = kind_spec.delete_suffix('*').delete_suffix('?')
      return PhysicalPosValue.money!(value, field) if kind == 'money'
      return nil_value(required, nullable, field) if value.nil?
      return OMIT if value == '' && !required

      case kind
      when 'string' then PhysicalPosValue.string!(value, field)
      when 'int' then PhysicalPosValue.integer!(value, field)
      when 'rowVersion' then PhysicalPosIdentifiers.row_version!(value, field)
      when 'bool' then PhysicalPosValue.boolean!(value, field)
      when 'strings' then PhysicalPosValue.strings!(value, field)
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
  end
end
