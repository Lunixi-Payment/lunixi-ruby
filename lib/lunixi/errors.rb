# frozen_string_literal: true

module Lunixi
  # Errors deliberately omit response bodies, request bodies and credentials.
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class SignatureError < Error; end
  class WebhookError < Error; end
  class ReplayConflict < WebhookError; end
  class TransportError < Error; end
  class RedirectError < Error; end

  class ApiError < Error
    # The only error `details` keys kept from a gateway answer; each value is a short identifier or a number.
    DETAIL_FIELDS = %w[field allowedOperation retryAfterSeconds].freeze
    SAFE_DETAIL = /\A[a-zA-Z0-9_.:\[\]?-]{1,200}\z/

    # details: the safe subset of the answer's details (DETAIL_FIELDS). idempotency_key: the key a
    # physical POS write sent, so a retry can reuse it.
    attr_reader :status, :code, :request_id, :retry_after, :details, :idempotency_key

    def initialize(status:, code: nil, request_id: nil, retry_after: nil, details: nil, idempotency_key: nil, message: nil)
      @status = status
      @code = safe_identifier(code)
      @request_id = safe_identifier(request_id)
      @retry_after = retry_after
      @details = self.class.safe_details(details)
      @idempotency_key = idempotency_key
      super(message || "Lunixi request failed (HTTP #{status})")
    end

    def self.safe_details(details)
      return {}.freeze unless details.is_a?(Hash)

      details.each_with_object({}) do |(name, value), safe|
        key = name.to_s
        next unless DETAIL_FIELDS.include?(key)

        safe[key] = value if value.is_a?(Integer) || value.is_a?(Float) || (value.is_a?(String) && value.match?(SAFE_DETAIL))
      end.freeze
    end

    private

    def safe_identifier(value)
      value if value.is_a?(String) && value.match?(/\A[a-zA-Z0-9_.:-]{1,200}\z/)
    end
  end

  class AuthenticationError < ApiError; end
  class ValidationError < ApiError; end
  class RateLimitError < ApiError; end

  # Physical POS: a request carries card data (a PAN, track, expiry or security-code field, or a card
  # number in merchantReference, an item name / tax group or a free-text filter). Raised locally before
  # anything is sent (status 0), or for the gateway's 400 physical_pos.payment.card_data_rejected.
  # field is the path of the offending field (items[1].cvv); the value never reaches the error.
  class PhysicalPosCardDataRejectedError < ValidationError
    CODE = 'physical_pos.payment.card_data_rejected'
    attr_reader :field

    def initialize(field: nil, **options)
      @field = field
      super(**{ code: CODE }.merge(options))
    end
  end

  # Physical POS: 429 RATE_LIMITED (payment writes are limited per API key). retry_after is the
  # Retry-After header in seconds, or details.retryAfterSeconds when the header is missing.
  class PhysicalPosRateLimitError < RateLimitError; end

  # Physical POS: the outcome of a payment write (start, reversal, cancel) is unknown; the payment may
  # or may not exist. Raised when an attempt got no HTTP answer, a 2xx without a readable payment, or a
  # 5xx that does not say "not started", and then for the whole call, whatever a later attempt answered
  # (a 429 or 409 included). Call again with the same idempotency_key (an existing payment comes back
  # with replayed: true), or look it up with list_payments(merchantReference:). A new key can start a
  # second payment. status / code are the last HTTP answer's (0 / nil when there was none); attempts is
  # the number of attempts made.
  class PhysicalPosOutcomeUnknownError < ApiError
    attr_reader :attempts

    def initialize(attempts: nil, **options)
      @attempts = attempts
      super(**options)
    end
  end

  # Physical POS: 409 physical_pos.payment.void_after_settlement. The payment is already in a device
  # end-of-day and can no longer be voided; return the amount with a REFUND reversal on the same payment
  # (with a new idempotency key). allowed_operation is details.allowedOperation (REFUND).
  class PhysicalPosVoidAfterSettlementError < ApiError
    CODE = 'physical_pos.payment.void_after_settlement'
    attr_reader :allowed_operation

    def initialize(allowed_operation: nil, **options)
      @allowed_operation = allowed_operation
      super(**{ code: CODE }.merge(options))
    end
  end
end
