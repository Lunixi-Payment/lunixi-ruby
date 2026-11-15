# frozen_string_literal: true

module Lunixi
  # The CSV of insurance.export_reconciliation. data: the file bytes (UTF-8 with BOM, one line per
  # policy, amounts in minor units). truncated: the file holds INSURANCE_EXPORT_ORDER_CAP orders and
  # next_cursor continues it (pass it as cursor:). aborted: the file ends with the gateway's abort line;
  # it is incomplete, request it again.
  InsuranceReconciliationExport = Struct.new(:data, :truncated, :next_cursor, :aborted, keyword_init: true) do
    def truncated?
      truncated == true
    end

    def aborted?
      aborted == true
    end

    def inspect
      "#<Lunixi::InsuranceReconciliationExport bytes=#{data.bytesize} truncated=#{truncated} aborted=#{aborted}>"
    end
  end

  # Local checks of the insurance requests and filters. Type objects (insured, tickets ...) are sent as
  # given: their field rules are the gateway's. Not a public API.
  module InsuranceRequest
    UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
    CURSOR_MAX_LENGTH = 512
    TEXT_MAX_LENGTH = 128
    CODE_MAX_LENGTH = 64
    TRUNCATED_LINE = /\A# truncated=true orderCap=(\d+) nextCursor=(\S+)\s*\z/
    ABORTED_LINE = /\A# export-aborted=true\s*\z/

    module_function

    # The query of a read route (INSURANCE_FILTERS); nil and '' are left out.
    def query!(filters, route, required = [])
      given = RouteRequest.wire_keys!(filters || {}, INSURANCE_FILTERS.fetch(route), 'insurance', 'filter')
      query = given.each_with_object({}) do |(key, value), out|
        out[key] = filter_value(key, value) unless value == ''
      end
      missing = required.reject { |key| query.key?(key) }
      raise ConfigurationError, "#{route} requires #{missing.map { |key| "'#{key}'" }.join(' and ')}." unless missing.empty?

      query
    end

    def filter_value(key, value)
      case key
      when 'limit'
        unless value.is_a?(Integer) && value.between?(1, INSURANCE_MAX_LIMIT)
          raise ConfigurationError, "'limit' must be an integer from 1 to #{INSURANCE_MAX_LIMIT}."
        end

        value
      when 'cursor'
        unless value.is_a?(String) && value.length <= CURSOR_MAX_LENGTH
          raise ConfigurationError, "'cursor' must be the next_cursor of the previous page, passed back unchanged."
        end

        value
      when 'currency' then RouteValue.currency!(value, key)
      when 'paymentIntentId', 'connectionId' then uuid!(value, key)
      when 'from', 'to' then RouteValue.iso_time!(value, key)
      when 'merchantOrderId' then RouteValue.text!(value, key, TEXT_MAX_LENGTH)
      when 'status' then lead_status!(value)
      else RouteValue.text!(value, key, CODE_MAX_LENGTH)
      end
    end

    def lead_status!(value)
      return value if InsuranceLeadStatus::ALL.include?(value)

      raise ConfigurationError, "'status' must be one of #{InsuranceLeadStatus::ALL.join(', ')}."
    end

    def uuid!(value, field)
      id = value.is_a?(String) ? value.strip : ''
      raise ConfigurationError, "'#{field}' must be a Lunixi id (UUID)." unless id.match?(UUID)

      id
    end

    def reference_kind!(kind)
      return kind if InsuranceReferenceKind::ALL.include?(kind)

      raise ConfigurationError, "Reference kind must be one of #{InsuranceReferenceKind::ALL.join(', ')}."
    end

    # context: { items } — the basket items the payment carries (1–100 Hashes, sent as given).
    def context!(value)
      context = RouteRequest.wire_keys!(value, %w[items], 'context')
      items = context['items']
      unless items.is_a?(Array) && items.length.between?(1, INSURANCE_MAX_CONTEXT_ITEMS) && items.all?(Hash)
        raise ConfigurationError, "'context.items' must hold 1 to #{INSURANCE_MAX_CONTEXT_ITEMS} basket items."
      end

      { 'items' => items }
    end

    def required_key!(key, operation)
      if key.nil? || key == ''
        raise ConfigurationError, "A stable Idempotency-Key is required for #{operation}. Reuse the same key when retrying the same operation."
      end

      RouteRequest.printable_idempotency_key!(key)
    end

    def optional_key(key)
      key.nil? || key == '' ? nil : RouteRequest.printable_idempotency_key!(key)
    end

    def positive_minor!(value, field)
      Money.minor(value, positive: true)
    rescue ConfigurationError
      raise ConfigurationError, "'#{field}' must be a positive canonical minor-unit string such as \"4990\" (not a number).", cause: nil
    end

    # The lead note is free text sent as given (not trimmed), at most 1000 characters.
    def lead_note!(value)
      raise ConfigurationError, "'note' must be a string." unless value.is_a?(String)
      raise ConfigurationError, "'note' must be at most #{INSURANCE_LEAD_NOTE_MAX_LENGTH} characters." if value.length > INSURANCE_LEAD_NOTE_MAX_LENGTH

      value
    end

    def export(bytes)
      text = bytes.dup.force_encoding(Encoding::UTF_8)
      text = text.scrub('') unless text.valid_encoding?
      last = text.split(/\r?\n/).reject(&:empty?).last.to_s
      truncated = TRUNCATED_LINE.match(last)
      InsuranceReconciliationExport.new(data: bytes, truncated: !truncated.nil?, next_cursor: truncated ? truncated[2] : nil,
                                        aborted: last.match?(ABORTED_LINE))
    end
  end
end
