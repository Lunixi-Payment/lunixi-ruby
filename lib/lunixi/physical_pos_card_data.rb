# frozen_string_literal: true

module Lunixi
  # The gateway's card-data rules for physical POS requests: card-data field names (any depth of a body
  # or filter set) and the refusal of card data, field names and card numbers in free text (read by
  # PhysicalPosCardNumber). The card is read on the device; a request never carries card data.
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

    CARD_DATA_TERMS = (NUMBER_TERMS + SECRET_TERMS).freeze
    CARD_DATA_MESSAGE = 'Physical POS requests must not contain card data: the card is read on the device. Remove the field ' \
                        'or value; do not send card numbers, expiry dates or security codes.'

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
      tokens[start..].any? do |token|
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

    def card_data_rejected(field)
      PhysicalPosCardDataRejectedError.new(status: 0, field: field, message: "#{CARD_DATA_MESSAGE} Field: #{field}.")
    end

    def reject_card_data!(value, root)
      field = find_card_data_field(value, root)
      raise card_data_rejected(field) unless field.nil?
    end

    # Card-number values in the free-text fields the gateway scans (the value never reaches the error).
    def reject_card_numbers!(body)
      raise card_data_rejected('merchantReference') if PhysicalPosCardNumber.contains_pan_like_value?(body['merchantReference'])

      Array(body['items']).each_with_index do |item, index|
        raise card_data_rejected("items[#{index}].name") if PhysicalPosCardNumber.contains_pan_like_value?(item['name'], PhysicalPosCardNumber::ITEM_TEXT)
        raise card_data_rejected("items[#{index}].taxGroupCode") if PhysicalPosCardNumber.contains_pan_like_value?(item['taxGroupCode'])
      end
    end
  end
end
