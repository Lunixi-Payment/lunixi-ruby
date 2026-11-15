# frozen_string_literal: true

module Lunixi
  # Canonical public fiat money. Arithmetic uses Ruby's exact Integer only after validation.
  module Money
    MAX = 9_223_372_036_854_775_807
    EXPONENTS = %w[TRY USD EUR GBP RUB AED SAR QAR CHF CAD AUD CNY AZN].to_h { |c| [c, 2] }.merge('JPY' => 0, 'KWD' => 3).freeze
    # Money members of the subscription and marketplace contracts: canonical minor-unit strings, signed
    # only for balances. The same list as the Node SDK's validateWireMoney.
    WIRE_FIELDS = %w[
      amount amountMinor price priceAmount paidAmount totalAmount subtotalAmount taxAmount amountPaid
      legAmount chargeAmount capturedAmount refundedAmount authorizedAmount compensatedAmount
      requestedAmount refundableAmount nonRefundableAmount disputedAmount legsAmount
      minAmount maxAmount minAmountMinor maxAmountMinor unitPriceMinor collectedAmountMinor
      premiumAmount collectedPremiumAmount inForcePremiumAmount cancelledPremiumAmount
      refundedPremiumAmount refundOpenPremiumAmount insuranceValueAmount priceSnapshotAmount
      sourceAmountMinor targetAmountMinor taxAmountMinor balanceMinor balanceAfterMinor
      availableMinor blockedMinor availableWithoutOverdraftMinor overdraftAvailableMinor
      sourceBalanceAfterMinor targetBalanceAfterMinor balance availableBalance blockedBalance
      feeAmount feeAmountMinor fixedAmountMinor minTransactionMinor commissionAmountMinor payoutAmountMinor
      settlementAmountMinor netAmountMinor grossAmountMinor fixedAmount fixedFee fixedFeeMinor mtdVolumeMinor
      orderAmountMinor capturedAmountMinor cumulativeCapturedMinor remainingCapturableMinor
      refundAmountMinor cumulativeRefundedMinor remainingRefundableMinor netAmount grossAmount
    ].freeze
    # Closed schema containers of those contracts; metadata, custom fields and provider bodies are opaque.
    WIRE_CONTAINERS = %w[
      data items legs steps pendingSteps schedule promissoryNote notes
      aggregate refund dispute details payment basketItems sellers scenario
      counters balances totals orders policies options quote order transfer
      commission commissionRule fee settlement payout context
    ].freeze
    WIRE_SIGNED_FIELDS = %w[availableMinor availableWithoutOverdraftMinor].freeze

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

    # Subscription and marketplace bodies, filters and answers: every WIRE_FIELDS member is a canonical
    # minor-unit string ("0" allowed; signed only for balances), checked the same way in both directions
    # without coercion. The error names the field, never its value.
    def validate_wire(value)
      case value
      when Array
        value.each { |entry| validate_wire(entry) }
      when Hash
        value.each do |name, entry|
          key = name.to_s
          next if entry.nil?

          if WIRE_FIELDS.include?(key)
            wire_minor!(entry, key, positive: false, signed: key.downcase.include?('balance') || WIRE_SIGNED_FIELDS.include?(key))
          elsif key == 'suggestedAmountsMinor'
            raise ConfigurationError, 'suggestedAmountsMinor must be an array.' unless entry.is_a?(Array)

            entry.each { |amount| wire_minor!(amount, key) }
          elsif WIRE_CONTAINERS.include?(key)
            validate_wire(entry)
          end
        end
      end
      value
    end

    # minor with the field named in the error.
    def wire_minor!(value, field, positive: true, signed: false)
      minor(value, positive: positive, signed: signed)
    rescue ConfigurationError
      raise ConfigurationError, "#{field} must be a canonical string in minor units (e.g. \"9900\" for 99.00).", cause: nil
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
            amount amountMinor authorizedAmount availableBalance availableMinor availableWithoutOverdraftMinor balanceAfterMinor
            balanceMinor blockedMinor buyerTotalCharge cancelledPremiumAmount
            capturedAmount capturedAmountMinor chargeAmount collectedAmountMinor collectedPremiumAmount compensatedAmount
            disputedAmount feeTotal fixedFee inForcePremiumAmount insuranceValueAmount legAmount legsAmount lineTotalMinor
            maxAmount maxAmountMinor minAmount minAmountMinor nonRefundableAmount overdraftAvailableMinor paidAmount paidPrice pendingBalance
            premiumAmount price refundAmount refundOpenPremiumAmount refundableAmount refundedAmount refundedAmountMinor
            refundedPremiumAmount requestedAmount reservedBalance sourceAmountMinor sourceBalanceAfterMinor targetAmountMinor
            targetBalanceAfterMinor taxAmountMinor taxTotal
            totalAmount unitPriceMinor
          ].include?(key)
            minor(entry, positive: !response && %w[amount price totalAmount].include?(key), signed: key.downcase.include?('balance'))
          elsif %w[
            data details items rows results payments operations balances wallets legs aggregate refund refunds totals
            charge fees fee balance splits sellers basketItems promissoryNote schedule notes lines offers policies
            reconciliation quotes payment transactions accounts settlements payouts limits options quote
          ].include?(key)
            validate_fields(entry, response: response)
          end
        end
      end
      value
    end
  end
end
