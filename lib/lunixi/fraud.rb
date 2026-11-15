# frozen_string_literal: true

module Lunixi
  class Fraud
    FIELDS = %w[integrationMode productContext transactionRef channel surface stage operationKind authModeRequested
                authModeApplied subMerchantRef subjectType subjectId paymentRail transferDirection merchantGroupIds
                paymentId payment bankTransfer cryptoTransfer walletOperation billPayment loanApplication payout
                customer device session merchant mobileApp telemetry metadata identitySnapshot identityAssertion].freeze

    # Transaction event ingest (signed) and the persisted decision log.
    attr_reader :events, :decisions

    def initialize(client)
      @client = client
      @events = FraudEvents.new(client)
      @decisions = FraudDecisions.new(client)
    end

    # Evaluate the documented fraud DTO; tenant identity comes from credentials.
    def evaluate(body)
      raise ConfigurationError, 'Fraud request must be an object' unless body.is_a?(Hash)

      data = JSON.parse(JsonBody.dump(body))
      raise ConfigurationError, 'Fraud request contains an unknown root field' unless (data.keys - FIELDS).empty?

      @client.request('POST', '/api/v1/fraud/decisions/evaluate', body: data, signed: false)
    end

    # Record a signed transaction event with a persisted operation idempotency key; same as events.record.
    def record_event(body, idempotency_key:)
      events.record(body, idempotency_key: idempotency_key)
    end
  end

  # Transaction events (POST /fraud/events/transactions[/batch]). Both routes are signed: the signature
  # binds the event to your merchant, so a body value cannot claim another one.
  class FraudEvents
    BASE = '/api/v1/fraud/events/transactions'
    REQUIRED_FIELDS = %w[eventId subjectType eventType occurredAt].freeze
    # The gateway rejects the whole batch above this size.
    BATCH_LIMIT = 500

    def initialize(client)
      @client = client
    end

    # One event with eventId, subjectType, eventType and occurredAt. Retrying with the same eventId is
    # deduplicated by the gateway.
    def record(body, idempotency_key:)
      event!(body, 'Fraud event')
      @client.request('POST', BASE, body: body, idempotency_key: Client.idempotency_key!(idempotency_key))
    end

    # Up to BATCH_LIMIT events in one call, sent as a JSON array. The batch can succeed partially: read
    # the per-event results in data.
    def record_batch(events, idempotency_key:)
      unless events.is_a?(Array) && !events.empty? && events.size <= BATCH_LIMIT
        raise ConfigurationError, "Fraud event batch must be a nonempty array of at most #{BATCH_LIMIT} events"
      end

      events.each_with_index { |event, index| event!(event, "events[#{index}]") }
      @client.request('POST', "#{BASE}/batch", body: events, idempotency_key: Client.idempotency_key!(idempotency_key))
    end

    private

    def event!(body, name)
      return if body.is_a?(Hash) && REQUIRED_FIELDS.all? { |field| body[field] || body[field.to_sym] }

      raise ConfigurationError, "#{name} requires #{REQUIRED_FIELDS.join(', ')}"
    end
  end

  # Persisted fraud decisions (GET /fraud/decision-logs). Lists are the gateway envelope: data is the
  # page of decisions and pageInfo (a sibling of data) carries hasMore and nextCursor.
  class FraudDecisions
    BASE = '/api/v1/fraud/decision-logs'
    LIST_FILTERS = %w[paymentId decision integrationMode productContext limit cursor].freeze

    def initialize(client)
      @client = client
    end

    # Filters: LIST_FILTERS; pass the previous page's pageInfo.nextCursor as cursor.
    def list(**filters)
      data = filters.transform_keys(&:to_s)
      unknown = data.keys - LIST_FILTERS
      raise ConfigurationError, "fraud.decisions.list does not take #{unknown.join(', ')}; filters: #{LIST_FILTERS.join(', ')}" unless unknown.empty?

      query = data.reject { |_, value| value.nil? || value == '' }
      @client.request('GET', BASE, query: query, signed: false)
    end

    # One decision by its trace id.
    def get(trace_id)
      raise ConfigurationError, 'trace_id is required' unless trace_id.is_a?(String) && trace_id.match?(/\A[a-zA-Z0-9_-]{1,256}\z/)

      @client.request('GET', "#{BASE}/#{trace_id}", signed: false)
    end

    # The most recent decision of a payment (a Hash), or nil when there is none.
    def latest_for_payment(payment_id)
      raise ConfigurationError, 'payment_id is required' unless payment_id.is_a?(String) && !payment_id.strip.empty?

      page = list(paymentId: payment_id, limit: 1)
      items = page['data']
      items.is_a?(Array) && items.first.is_a?(Hash) ? items.first : nil
    end
  end
end
