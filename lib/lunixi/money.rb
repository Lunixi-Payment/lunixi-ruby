# frozen_string_literal: true

module Lunixi
  # Canonical public fiat money. Arithmetic uses Ruby's exact Integer only after validation.
  module Money
    MAX = 9_223_372_036_854_775_807
    EXPONENTS = %w[TRY USD EUR GBP RUB AED SAR QAR CHF CAD AUD CNY AZN].to_h { |c| [c, 2] }.merge('JPY' => 0, 'KWD' => 3).freeze
    module_function

    def fiat_route?(path)
      path.match?(%r{\A/api/v1/(?:payments|wallet|insurance|bank-connect|fraud)(?:[/?]|\z)})
    end

    def validate_operation_amount(path, body)
      return unless path.match?(%r{\A/api/v1/payments/(?:split/)?[^/]+/(?:capture|refund)(?:[?]|\z)}) && body.is_a?(Hash)

      body.each { |key, value| minor(value) if key.to_s == 'amount' }
    end

    def minor(value, positive: true, signed: false)
      pattern = if signed
                  /\A(?:0|-?[1-9][0-9]*)\z/
                elsif positive
                  /\A[1-9][0-9]*\z/
                else
                  /\A(?:0|[1-9][0-9]*)\z/
                end
      unless value.is_a?(String) && value.match?(pattern) && value.to_i.between?(-MAX - 1, MAX)
        raise ConfigurationError, 'Canonical minor-unit string in the signed 64-bit fiat range required'
      end

      value
    end

    def decimal_to_minor(value, currency)
      exponent = EXPONENTS.fetch(currency) { raise ConfigurationError, 'Unsupported currency' }
      raise ConfigurationError, 'Exact decimal text required' unless value.is_a?(String) && value.match?(/\A(?:0|[1-9][0-9]*)(?:\.[0-9]+)?\z/)

      whole, fraction = value.split('.', 2)
      fraction ||= ''
      raise ConfigurationError, 'Fractional minor units' if fraction[exponent..]&.match?(/[1-9]/)

      minor((whole + fraction[0, exponent].ljust(exponent, '0')).to_i.to_s, positive: false)
    end

    def validate_fields(value, response: false)
      case value
      when Array
        value.each { |entry| validate_fields(entry, response: response) }
      when Hash
        value.each do |name, entry|
          key = name.to_s
          next if entry.nil? || %w[metadata fields inputFields insuranceData].include?(key)

          if %w[
            amount amountMinor authorizedAmount availableBalance balanceMinor buyerTotalCharge cancelledPremiumAmount
            capturedAmount capturedAmountMinor chargeAmount collectedAmountMinor collectedPremiumAmount compensatedAmount
            disputedAmount feeTotal fixedFee inForcePremiumAmount insuranceValueAmount legAmount legsAmount lineTotalMinor
            maxAmount maxAmountMinor minAmount minAmountMinor nonRefundableAmount paidAmount paidPrice pendingBalance
            premiumAmount price refundAmount refundOpenPremiumAmount refundableAmount refundedAmount refundedAmountMinor
            refundedPremiumAmount requestedAmount reservedBalance sourceAmountMinor targetAmountMinor taxAmountMinor taxTotal
            totalAmount unitPriceMinor
          ].include?(key)
            minor(entry, positive: !response && %w[amount price totalAmount].include?(key), signed: key.downcase.include?('balance'))
          elsif %w[
            data details items rows results payments operations balances wallets legs aggregate refund refunds totals
            charge fees fee balance splits sellers basketItems promissoryNote schedule notes lines offers policies
            reconciliation quotes payment transactions accounts settlements payouts limits
          ].include?(key)
            validate_fields(entry, response: response)
          end
        end
      end
      value
    end
  end
end
