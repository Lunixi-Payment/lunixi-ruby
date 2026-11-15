# frozen_string_literal: true

module Lunixi
  # Single values of the physical POS bodies and filters: strings, JSON integers, booleans, string lists
  # and canonical minor-unit money. The error names the field, never its value. Not a public API.
  module PhysicalPosValue
    MAX_SAFE_INTEGER = JsonBody::MAX_SAFE_INTEGER

    module_function

    def string!(value, field)
      raise ConfigurationError, "'#{field}' must be a non-empty string." unless value.is_a?(String) && !value.empty?

      value
    end

    def integer!(value, field)
      raise ConfigurationError, "'#{field}' must be an integer (a JSON number, not a string)." unless value.is_a?(Integer) && value.abs <= MAX_SAFE_INTEGER

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
  end
end
