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
    attr_reader :status, :code, :request_id, :retry_after

    def initialize(status:, code: nil, request_id: nil, retry_after: nil)
      @status = status
      @code = safe_identifier(code)
      @request_id = safe_identifier(request_id)
      @retry_after = retry_after
      super("Lunixi request failed (HTTP #{status})")
    end

    private

    def safe_identifier(value)
      value if value.is_a?(String) && value.match?(/\A[a-zA-Z0-9_.:-]{1,200}\z/)
    end
  end

  class AuthenticationError < ApiError; end
  class ValidationError < ApiError; end
  class RateLimitError < ApiError; end
end
