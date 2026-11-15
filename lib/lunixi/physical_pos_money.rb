# frozen_string_literal: true

module Lunixi
  # Declared physical POS money in responses and webhooks: canonical minor-unit strings ("4500").
  # Counts, rates and opaque metadata stay untouched; net* fields and everything under difference may be
  # negative.
  module PhysicalPosMoney
    FIELDS = %w[
      amountFromMinor amountMinor amountToMinor approvedAmountMinor baseMinor capturedMinor lineTotalMinor netBaseMinor
      netMinor netTaxMinor refundBaseMinor refundMinor refundTaxMinor refundedAmountMinor refundedMinor reservedAmountMinor
      reservedMinor reversalReservedMinor reversedMinor saleBaseMinor saleMinor saleTaxMinor unitAmountMinor unitPriceMinor
      voidBaseMinor voidMinor voidTaxMinor
    ].freeze
    CONTAINERS = %w[
      data payment payments items refundItems taxes rows transaction transactions root children itemSummary amountTotals
      reported system difference totals lines
    ].freeze
    NULLABLE = %w[approvedAmountMinor unitAmountMinor].freeze

    module_function

    def validate(value, difference = false)
      case value
      when Array then value.each { |entry| validate(entry, difference) }
      when Hash
        value.each do |name, entry|
          key = name.to_s
          if FIELDS.include?(key)
            next if entry.nil? && NULLABLE.include?(key)

            amount!(entry, key, difference || key.start_with?('net'))
          elsif CONTAINERS.include?(key)
            validate(entry, difference || key == 'difference')
          end
        end
      end
      value
    end

    def amount!(value, key, signed)
      Money.minor(value, positive: false, signed: signed)
    rescue ConfigurationError
      raise ConfigurationError, "The physical POS answer carries a non-canonical amount in '#{key}' (minor-unit string expected)", cause: nil
    end
  end
end
