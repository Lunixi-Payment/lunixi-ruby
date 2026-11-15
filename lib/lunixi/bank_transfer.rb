# frozen_string_literal: true

module Lunixi
  # Para Transferi (BANK_TRANSFER): the buyer sends the money from their own bank to the merchant's
  # bank account; the incoming transaction is matched to the payment by the payment code in the
  # description (or by the exact amount when there is no code).
  #
  # The "Other banks" option of the bankCode field: the buyer pays by EFT/FAST from a bank not listed.
  BANK_TRANSFER_OTHER_BANKS_CODE = '9999'
  # Most items payments.list_bank_transfer_exceptions returns per call.
  BANK_TRANSFER_EXCEPTION_LIMIT_MAX = 200

  # Kind of a bank transfer exception.
  module PaymentBankTransferExceptionKind
    # Arrived after the deadline.
    LATE = 'LATE'
    # The deadline passed with less than expected; the payment waits for your decision.
    UNDERPAID = 'UNDERPAID'
    # More than expected arrived; refund the excess.
    OVERPAID = 'OVERPAID'

    ALL = [LATE, UNDERPAID, OVERPAID].freeze
  end

  # Status of a bank transfer exception.
  module PaymentBankTransferExceptionStatus
    PENDING_DECISION = 'PENDING_DECISION'
    ACCEPTED = 'ACCEPTED'
    REFUND_PENDING = 'REFUND_PENDING'
    REFUNDED = 'REFUNDED'

    ALL = [PENDING_DECISION, ACCEPTED, REFUND_PENDING, REFUNDED].freeze
  end

  # Webhook events of a BANK_TRANSFER payment (payment.* envelope, payload bankTransfer). They do not
  # change the payment status: the outcome is still payment.captured / payment.failed.
  module PaymentBankTransferEvents
    PARTIALLY_RECEIVED = 'payment.bank_transfer.partially_received'
    UNDERPAID = 'payment.bank_transfer.underpaid'
    OVERPAID = 'payment.bank_transfer.overpaid'
    LATE_ARRIVAL = 'payment.bank_transfer.late_arrival'

    ALL = [PARTIALLY_RECEIVED, UNDERPAID, OVERPAID, LATE_ARRIVAL].freeze
  end

  # Transfer instruction of a BANK_TRANSFER payment (DISPLAY action, data.action.bankTransfer): the
  # merchant's bank account to show the buyer. other_bank is true when the buyer chose "Other banks".
  BankTransferInstruction = Struct.new(:bank_code, :bank_name, :holder_name, :iban, :amount_minor, :currency,
                                       :payment_code, :expires_at, :other_bank, keyword_init: true) do
    # Reads data.action.bankTransfer of a gateway response envelope (or of its data hash). Returns nil
    # when there is no action, the action is not DISPLAY or it carries no transfer instruction.
    def self.from_response(response)
      return nil unless response.is_a?(Hash)

      data = response.key?('data') ? response['data'] : response
      action = data.is_a?(Hash) ? data['action'] : nil
      return nil unless action.is_a?(Hash) && action['type'] == PaymentActionType::DISPLAY

      instruction = action['bankTransfer']
      return nil unless instruction.is_a?(Hash)

      new(bank_code: instruction['bankCode'], bank_name: instruction['bankName'], holder_name: instruction['holderName'],
          iban: instruction['iban'], amount_minor: instruction['amountMinor'], currency: instruction['currency'],
          payment_code: instruction['paymentCode'], expires_at: instruction['expiresAt'], other_bank: instruction['otherBank'] == true)
    end
  end

  # Query and path rules of the bank transfer exception endpoints.
  module BankTransferExceptions
    ENVIRONMENTS = %w[TEST LIVE].freeze
    UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

    module_function

    # Query of GET /payments/bank-transfer/exceptions; empty filters are not sent.
    def query!(environment: nil, status: nil, limit: nil)
      query = {}
      unless environment.nil?
        raise ConfigurationError, "environment must be one of #{ENVIRONMENTS.join(', ')}" unless ENVIRONMENTS.include?(environment)

        query['environment'] = environment
      end
      unless status.nil?
        unless PaymentBankTransferExceptionStatus::ALL.include?(status)
          raise ConfigurationError, "status must be one of #{PaymentBankTransferExceptionStatus::ALL.join(', ')}"
        end

        query['status'] = status
      end
      unless limit.nil?
        unless limit.is_a?(Integer) && limit.between?(1, BANK_TRANSFER_EXCEPTION_LIMIT_MAX)
          raise ConfigurationError, "limit must be an integer between 1 and #{BANK_TRANSFER_EXCEPTION_LIMIT_MAX}"
        end

        query['limit'] = limit.to_s
      end
      query
    end

    def exception_id!(value)
      return value if value.is_a?(String) && value.match?(UUID_PATTERN)

      raise ConfigurationError, 'exception_id must be the UUID of a bank transfer exception (items[].id)'
    end
  end
end
