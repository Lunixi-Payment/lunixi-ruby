# frozen_string_literal: true

module Lunixi
  # The gateway's card-data rules for physical POS requests: card-data field names (any depth of a body
  # or filter set) and card numbers written into free-text values. The card is read on the device; a
  # request never carries card data.
  module PhysicalPosCardData
    NUMBER_TERMS = %w[pan pannumber cardpan cardnumber cardno cardnum cardnr ccnumber ccnum primaryaccountnumber].freeze
    SECRET_TERMS = %w[
      cvv cvv2 cvc cvc2 cvn cvn2 cav2 cvvcode cvccode cardcode securitycode cardverificationcode cardverificationvalue
      track1 track2 track3 tracki trackii trackiii trackdata magstripe magneticstripe pinblock pincode pinnumber pindata
      cardpin cardholderpin encryptedpin expdate expmonth expyear expmmyy expirydate expirymonth expiryyear expirymmyy
      expirationdate expirationmonth expirationyear expiremonth expireyear cardexpiry cardexpiration
    ].freeze
    SUFFIX_TERMS = %w[
      cardnumber pannumber primaryaccountnumber cvv cvv2 cvc cvc2 cvvcode securitycode track1 track2 trackdata pinblock
      expmonth expyear expirydate expirymonth expiryyear expirationdate cardexpiry
    ].freeze
    WHOLE_KEY_TERMS = %w[track expiry expiration pin cid csc].freeze
    MASK_TOKENS = %w[masked mask].freeze

    # Term lists of the card-data key rule (the parity test compares them with the shared fixture).
    KEY_RULE = {
      'numberTerms' => NUMBER_TERMS, 'secretTerms' => SECRET_TERMS, 'suffixTerms' => SUFFIX_TERMS,
      'wholeKeyTerms' => WHOLE_KEY_TERMS, 'maskTokens' => MASK_TOKENS
    }.freeze

    DIGIT_RUN_KEY_SOURCE = '[0-9](?:[ -]?[0-9]){12,}'
    DIGIT_RUN_KEY = Regexp.new(DIGIT_RUN_KEY_SOURCE)
    IDENTIFIER_KEY = /\A[A-Za-z_$][A-Za-z0-9_$]*\z/
    PAN_CANDIDATE = /(?<![\p{L}\p{N}])(?<![\p{L}\p{N}]-)[0-9](?:[ -]?[0-9]){12,18}(?![\p{L}\p{N}])(?!-[\p{L}\p{N}])/
    GTIN = /\A(?:[0-9]{8}|[0-9]{12,14})\z/

    # contains_pan_like_value? modes: STRICT for every scanned field, ITEM_TEXT for item names (an
    # unseparated 13 or 14 digit number with a valid GTIN check digit is a barcode, not a card).
    STRICT = 'STRICT'
    ITEM_TEXT = 'ITEM_TEXT'

    CARD_DATA_TERMS = (NUMBER_TERMS + SECRET_TERMS).freeze

    module_function

    def key_tokens(key)
      key.to_s
         .gsub(/([a-z0-9])([A-Z])/, '\1 \2')
         .gsub(/([A-Z]+)([A-Z][a-z])/, '\1 \2')
         .gsub(/([A-Za-z])([0-9])/, '\1 \2')
         .gsub(/([0-9])([A-Za-z])/, '\1 \2')
         .downcase
         .split(/[^a-z0-9]+/)
         .reject(&:empty?)
    end

    # True when a field name is card data (pan, cardNumber, cvv, track2Data, expiryDate …).
    def card_data_key?(key)
      tokens = key_tokens(key)
      return false if tokens.empty?
      return true if WHOLE_KEY_TERMS.include?(tokens.join)

      masked = tokens.any? { |token| MASK_TOKENS.include?(token) }
      tokens.each_index.any? { |start| card_data_run?(tokens, start, masked) }
    end

    def card_data_run?(tokens, start, masked)
      joined = +''
      tokens[start..-1].any? do |token|
        joined << token
        next true if CARD_DATA_TERMS.include?(joined) && !(masked && NUMBER_TERMS.include?(joined))

        SUFFIX_TERMS.any? { |term| joined.end_with?(term) && !(masked && NUMBER_TERMS.include?(term)) }
      end
    end

    # Path of the first card-data key in a body or filter set (items[1].cvv), or nil. A key holding a
    # 13+ digit run stops at the parent path. Values are not read here.
    def find_card_data_field(value, root = '(body)')
      stack = [[value, '']]
      until stack.empty?
        node, path = stack.pop
        if node.is_a?(Array)
          (node.size - 1).downto(0) { |index| stack << [node[index], "#{path}[#{index}]"] }
          next
        end
        next unless node.is_a?(Hash)

        keys = node.keys
        keys.each do |key|
          return path.empty? ? root : path if key.to_s.match?(DIGIT_RUN_KEY)
          return child_path(path, key) if card_data_key?(key)
        end
        keys.reverse_each { |key| stack << [node[key], child_path(path, key)] }
      end
      nil
    end

    def child_path(path, key)
      name = key.to_s
      return "#{path}[?]" unless name.match?(IDENTIFIER_KEY)

      path.empty? ? name : "#{path}.#{name}"
    end

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
