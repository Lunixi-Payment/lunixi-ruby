# frozen_string_literal: true

require 'json'

module Lunixi
  # JSON bytes compatible with JSON.parse followed by JSON.stringify at the gateway.
  # Ruby hashes preserve insertion order; JavaScript moves array-index keys first.
  module JsonBody
    MAX_SAFE_INTEGER = 9_007_199_254_740_991
    MAX_DEPTH = 64

    module_function

    def dump(value)
      encode(value, 0).freeze
    rescue JSON::GeneratorError, EncodingError
      raise ConfigurationError, 'Request contains invalid JSON text', cause: nil
    end

    def encode(value, depth)
      raise ConfigurationError, 'Request JSON nesting is too deep' if depth > MAX_DEPTH

      case value
      when Hash then encode_hash(value, depth)
      when Array then "[#{value.map { |entry| encode(entry, depth + 1) }.join(',')}]"
      when String
        utf8 = value.encode(Encoding::UTF_8)
        raise ConfigurationError, 'Request contains invalid UTF-8' unless utf8.valid_encoding?

        JSON.generate(utf8)
      when Integer
        raise ConfigurationError, 'JSON integer exceeds the JavaScript safe range; use a documented digit-string field' if value.abs > MAX_SAFE_INTEGER

        value.to_s
      when Float then float_number(value)
      when true then 'true'
      when false then 'false'
      when nil then 'null'
      else raise ConfigurationError, 'Request contains an unsupported JSON value'
      end
    end

    def encode_hash(value, depth)
      pairs = {}
      value.each do |key, entry|
        raise ConfigurationError, 'JSON object keys must be strings or symbols' unless key.is_a?(String) || key.is_a?(Symbol)

        name = key.to_s
        raise ConfigurationError, 'Duplicate normalized JSON key' if pairs.key?(name)

        pairs[name] = entry
      end
      indexed, ordinary = pairs.keys.partition { |key| array_index?(key) }
      ordered = indexed.sort_by(&:to_i) + ordinary
      "{#{ordered.map { |key| "#{encode(key, depth + 1)}:#{encode(pairs.fetch(key), depth + 1)}" }.join(',')}}"
    end

    def array_index?(key)
      key.match?(/\A(?:0|[1-9][0-9]{0,9})\z/) && key.to_i < 4_294_967_295
    end

    # Both runtimes use the shortest round-trippable decimal. ECMAScript expands
    # values in [1e-6, 1e21) and writes the exponent without leading zeroes.
    def float_number(value)
      raise ConfigurationError, 'JSON numbers must be finite' unless value.finite?
      return '0' if value.zero?

      sign = value.negative? ? '-' : ''
      mantissa, exponent = value.abs.to_s.downcase.split('e')
      exponent = exponent ? exponent.to_i : 0
      integer, fraction = mantissa.split('.')
      fraction = (fraction || '').sub(/0+\z/, '')
      digits = integer + fraction
      point = integer.length + exponent
      number = if value.abs >= 1e-6 && value.abs < 1e21
                 fixed_number(digits, point)
               else
                 scientific_number(digits, point, integer, exponent, mantissa)
               end
      sign + number
    end

    def fixed_number(digits, point)
      if point <= 0
        "0.#{'0' * -point}#{digits}"
      elsif point >= digits.length
        digits + ('0' * (point - digits.length))
      else
        "#{digits[0...point]}.#{digits[point..]}"
      end
    end

    def scientific_number(digits, point, integer, exponent, mantissa)
      significant = digits.sub(/\A0+/, '')
      decimal_exponent = point - integer.index(/[1-9]/).to_i - 1
      # Scientific Ruby output has one digit before the decimal point.
      decimal_exponent = exponent if mantissa.to_f >= 1 && mantissa.to_f < 10
      coefficient = significant[0] + (significant.length > 1 ? ".#{significant[1..]}" : '')
      exponent_text = decimal_exponent.negative? ? decimal_exponent.to_s : "+#{decimal_exponent}"
      "#{coefficient}e#{exponent_text}"
    end
  end
end
