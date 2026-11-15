# frozen_string_literal: true

module Lunixi
  # Single request values shared by the route-table clients: texts, currency codes, times and closed
  # value lists. Every check names the field, never its value. Not a public API.
  module RouteValue
    CURRENCY = /\A[A-Z]{3}\z/

    module_function

    # A trimmed non-empty String, at most max characters when given.
    def text!(value, field, max = nil)
      raise ConfigurationError, "'#{field}' is required." unless value.is_a?(String) && !value.strip.empty?

      text = value.strip
      raise ConfigurationError, "'#{field}' must be at most #{max} characters." if max && text.length > max

      text
    end

    def currency!(value, field)
      currency = value.is_a?(String) ? value.strip.upcase : ''
      raise ConfigurationError, "'#{field}' must be an ISO 4217 code such as TRY." unless currency.match?(CURRENCY)

      currency
    end

    # A Time (sent as ISO 8601 UTC) or an ISO 8601 string with a time zone (sent trimmed).
    def iso_time!(value, field)
      return value.getutc.strftime('%Y-%m-%dT%H:%M:%S.%LZ') if value.is_a?(Time)
      return value.strip if value.is_a?(String) && !value.strip.empty?

      raise ConfigurationError, "'#{field}' must be a Time or an ISO 8601 string with a time zone."
    end

    # The instant of a Time or an ISO 8601 string, nil when it cannot be read.
    def instant(value)
      return value if value.is_a?(Time)
      return nil unless value.is_a?(String) && !value.strip.empty?

      Time.iso8601(value.strip)
    rescue ArgumentError
      nil
    end

    # nil or '' is nil; anything else must be a String.
    def optional_text(value, field)
      return nil if value.nil? || value == ''
      raise ConfigurationError, "'#{field}' must be a string." unless value.is_a?(String)

      value
    end

    def one_of!(value, allowed, field)
      return value if allowed.include?(value)

      raise ConfigurationError, "'#{field}' must be one of #{allowed.join(', ')}."
    end
  end
end
