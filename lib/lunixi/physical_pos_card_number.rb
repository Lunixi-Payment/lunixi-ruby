# frozen_string_literal: true

module Lunixi
  # Card numbers written into the free-text values of a physical POS request (merchantReference, item
  # names, tax groups, free-text filters). Not a public API.
  module PhysicalPosCardNumber
    PAN_CANDIDATE = /(?<![\p{L}\p{N}])(?<![\p{L}\p{N}]-)[0-9](?:[ -]?[0-9]){12,18}(?![\p{L}\p{N}])(?!-[\p{L}\p{N}])/
    GTIN = /\A(?:[0-9]{8}|[0-9]{12,14})\z/

    # contains_pan_like_value? modes: STRICT for every scanned field, ITEM_TEXT for item names (an
    # unseparated 13 or 14 digit number with a valid GTIN check digit is a barcode, not a card).
    STRICT = 'STRICT'
    ITEM_TEXT = 'ITEM_TEXT'

    module_function

    # True when the text holds a stand-alone, Luhn-valid 13–19 digit number (plain, space or dash
    # separated). In ITEM_TEXT mode a valid unseparated 13 or 14 digit GTIN is a barcode.
    def contains_pan_like_value?(text, mode = STRICT)
      return false unless text.is_a?(String)

      utf8_text(text).scan(PAN_CANDIDATE).any? do |candidate|
        digits = candidate.delete(' -')
        next false unless digits.length.between?(13, 19)
        next false if mode == ITEM_TEXT && digits == candidate && digits.length <= 14 && gtin_valid?(digits)

        luhn_valid?(digits)
      end
    end

    def utf8_text(text)
      utf8 = text.encode(Encoding::UTF_8)
      raise ConfigurationError, 'Physical POS request text must be valid UTF-8' unless utf8.valid_encoding?

      utf8
    rescue EncodingError
      raise ConfigurationError, 'Physical POS request text must be valid UTF-8', cause: nil
    end

    def luhn_valid?(digits)
      sum = 0
      digits.reverse.each_char.with_index do |char, index|
        digit = char.to_i
        if index.odd?
          digit *= 2
          digit -= 9 if digit > 9
        end
        sum += digit
      end
      (sum % 10).zero?
    end

    def gtin_valid?(digits)
      return false unless digits.match?(GTIN)

      sum = 0
      weight = 3
      (digits.length - 2).downto(0) do |index|
        sum += digits[index].to_i * weight
        weight = weight == 3 ? 1 : 3
      end
      (10 - (sum % 10)) % 10 == digits[-1].to_i
    end
  end
end
