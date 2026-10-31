# frozen_string_literal: true

module Lunixi
  class Fraud
    FIELDS = %w[integrationMode productContext transactionRef channel surface stage operationKind authModeRequested
                authModeApplied subMerchantRef subjectType subjectId paymentRail transferDirection merchantGroupIds
                paymentId payment bankTransfer cryptoTransfer walletOperation billPayment loanApplication payout
                customer device session merchant mobileApp telemetry metadata identitySnapshot identityAssertion].freeze

    def initialize(client)
      @client = client
    end

    # Evaluate the documented fraud DTO; tenant identity comes from credentials.
    def evaluate(body)
      raise ConfigurationError, 'Fraud request must be an object' unless body.is_a?(Hash)

      data = JSON.parse(JsonBody.dump(body))
      raise ConfigurationError, 'Fraud request contains an unknown root field' unless (data.keys - FIELDS).empty?

      @client.request('POST', '/api/v1/fraud/decisions/evaluate', body: data, signed: false)
    end

    # Record a signed transaction event with a persisted operation idempotency key.
    def record_event(body, idempotency_key:)
      unless body.is_a?(Hash) && %w[eventId subjectType eventType occurredAt].all? { |name| body[name] || body[name.to_sym] }
        raise ConfigurationError, 'Fraud event requires eventId, subjectType, eventType and occurredAt'
      end

      @client.request('POST', '/api/v1/fraud/events/transactions', body: body,
                                                                   idempotency_key: Client.idempotency_key!(idempotency_key))
    end
  end
end
