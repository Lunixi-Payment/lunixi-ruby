# frozen_string_literal: true

module Lunixi
  # Canonical money of the subscription and marketplace contracts (bodies, filters and answers).
  module WireMoney
    # Money members of the subscription and marketplace contracts: canonical minor-unit strings, signed
    # only for balances. The same list as the Node SDK's validateWireMoney.
    FIELDS = %w[
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
    CONTAINERS = %w[
      data items legs steps pendingSteps schedule promissoryNote notes
      aggregate refund dispute details payment basketItems sellers scenario
      counters balances totals orders policies options quote order transfer
      commission commissionRule fee settlement payout context
    ].freeze
    SIGNED_FIELDS = %w[availableMinor availableWithoutOverdraftMinor].freeze

    module_function

    # Subscription and marketplace bodies, filters and answers: every FIELDS member is a canonical
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

          if FIELDS.include?(key)
            wire_minor!(entry, key, positive: false, signed: key.downcase.include?('balance') || SIGNED_FIELDS.include?(key))
          elsif key == 'suggestedAmountsMinor'
            raise ConfigurationError, 'suggestedAmountsMinor must be an array.' unless entry.is_a?(Array)

            entry.each { |amount| wire_minor!(amount, key) }
          elsif CONTAINERS.include?(key)
            validate_wire(entry)
          end
        end
      end
      value
    end

    # Money.minor with the field named in the error.
    def wire_minor!(value, field, positive: true, signed: false)
      Money.minor(value, positive: positive, signed: signed)
    rescue ConfigurationError
      raise ConfigurationError, "#{field} must be a canonical string in minor units (e.g. \"9900\" for 99.00).", cause: nil
    end
  end
end
