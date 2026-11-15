# frozen_string_literal: true

module Lunixi
  # Sends the physical POS requests of PhysicalPos and PhysicalPosManagement through Client#request
  # (signed, bearer token), checks the declared money of every answer and maps the errors. Payment
  # writes run their own attempt loop so an uncertain outcome is never lost. Not a public API.
  class PhysicalPosGateway
    AMBIGUOUS = :ambiguous
    NOT_STARTED = :not_started
    DEFINITE = :definite
    OUTCOME_UNKNOWN_MESSAGE = 'The outcome of the physical POS payment request is unknown: the payment may exist. Call again ' \
                              'with the same idempotency_key (an existing payment comes back with replayed: true) or look ' \
                              'it up; never use a new key for it.'

    def initialize(client, max_retries:, backoff:)
      @client = client
      @max_retries = max_retries
      @backoff = backoff
    end

    # One signed request (reads and management writes); answers are money-checked, errors mapped.
    def perform(method, path, body: nil, query: {}, idempotency_key: nil)
      response = @client.request(method, PhysicalPosRequest::BASE + path, body: body, query: query, idempotency_key: idempotency_key)
      PhysicalPosMoney.validate(response)
      response
    rescue ApiError => e
      mapped = PhysicalPosResponses.translate(e, idempotency_key)
      raise if mapped.equal?(e)

      raise mapped
    end

    def data(method, path, body: nil, query: {})
      PhysicalPosResponses.unwrap(perform(method, path, body: body, query: query))
    end

    # data[name] of a single-record answer (or data when the wrapper is missing).
    def record(method, path, name, body: nil, query: {})
      PhysicalPosResponses.member(perform(method, path, body: body, query: query), name)
    end

    def page(path, query)
      PhysicalPosResponses.page(perform('GET', path, query: query))
    end

    # A management or end-of-day write with an Idempotency-Key: the caller's key, or a new UUID for nil.
    def keyed_write(path, body, idempotency_key, fallback)
      key = PhysicalPosIdentifiers.idempotency_key_or_new(idempotency_key)
      PhysicalPosResponses.write_result(perform('POST', path, body: body, idempotency_key: key), key, fallback)
    end

    # Payment start, reversal or cancel: 1 + max_retries attempts with the same key and body (the
    # client's own retries are off for each attempt).
    #
    # Success is only a 2xx carrying a payment. A 2xx without a readable payment, no HTTP answer, or a
    # 5xx that does not say "not started" leaves the outcome unknown; it is retried while attempts
    # remain. A 4xx stops at once. When any attempt was ambiguous the call raises
    # PhysicalPosOutcomeUnknownError whatever the last answer was (a later 429 or 409 included),
    # because the key may already hold a payment.
    def payment_write(path, body, key, fallback)
      attempts = 1 + @max_retries
      ambiguous = false
      last_error = nil
      (1..attempts).each do |attempt|
        response, error, outcome = attempt_payment(path, body, key)
        if response
          result = written_payment(response, key, fallback)
          return result if result

          error = missing_payment(response)
          outcome = AMBIGUOUS
        end
        local_error!(error, ambiguous, key, attempt) if outcome.nil?
        last_error = error
        ambiguous ||= outcome == AMBIGUOUS
        if outcome == DEFINITE || attempt == attempts
          raise outcome_unknown(last_error, key, attempt), cause: last_error if ambiguous

          break
        end
        @backoff.call(attempt - 1)
      end
      definite!(last_error, key)
    end

    private

    # [response, nil, nil] for an answer, [nil, error, outcome] for a failed attempt; outcome nil marks
    # an error raised before anything was sent.
    def attempt_payment(path, body, key)
      response = @client.request('POST', PhysicalPosRequest::BASE + path, body: body, idempotency_key: key, max_retries: 0)
      [response, nil, nil]
    rescue ApiError => e
      [nil, e, attempt_outcome(e)]
    rescue StandardError => e
      [nil, e, raised_before_sending?(e) ? nil : AMBIGUOUS]
    end

    # An SDK error other than a transport or redirect failure (a local check) means nothing was sent.
    def raised_before_sending?(error)
      error.is_a?(Error) && !error.is_a?(TransportError) && !error.is_a?(RedirectError)
    end

    # - ambiguous: no HTTP answer, an unreadable 2xx, or a 5xx that does not say "not started".
    # - not_started: a 5xx with a code in PHYSICAL_POS_NOT_STARTED_CODES.
    # - definite: any other answer (4xx, 429 and 409 included).
    def attempt_outcome(error)
      return AMBIGUOUS if error.status.to_i.zero? || error.status.to_i.between?(200, 299)
      return DEFINITE if error.status.to_i < 500

      PHYSICAL_POS_NOT_STARTED_CODES.include?(error.code) ? NOT_STARTED : AMBIGUOUS
    end

    # A local refusal (nothing sent) after an earlier uncertain attempt still leaves the outcome unknown.
    def local_error!(error, ambiguous, key, attempt)
      raise error unless ambiguous

      raise outcome_unknown(error, key, attempt - 1), cause: error
    end

    def definite!(error, key)
      mapped = PhysicalPosResponses.translate(error, key)
      raise mapped if mapped.equal?(error)

      raise mapped, cause: error
    end

    def missing_payment(response)
      status = response.is_a?(Hash) && response['statusCode'].is_a?(Integer) ? response['statusCode'] : 0
      ApiError.new(status: status, message: 'The gateway accepted the payment request but the answer carries no payment.')
    end

    def written_payment(response, key, fallback)
      PhysicalPosMoney.validate(response)
      data = PhysicalPosResponses.unwrap(response)
      payment = data.is_a?(Hash) ? data['payment'] : nil
      return nil unless payment.is_a?(Hash) && payment['paymentId'].is_a?(String) && !payment['paymentId'].empty?

      PhysicalPosResponses.write_result(response, key, fallback)
    rescue ConfigurationError, SystemStackError
      nil
    end

    def outcome_unknown(last_error, key, attempts)
      answered = last_error.is_a?(ApiError) ? last_error : nil
      PhysicalPosOutcomeUnknownError.new(
        status: answered ? answered.status : 0, code: answered&.code, request_id: answered&.request_id,
        details: answered&.details, retry_after: answered ? PhysicalPosResponses.retry_after_seconds(answered) : nil,
        idempotency_key: key, attempts: attempts, message: OUTCOME_UNKNOWN_MESSAGE
      )
    end
  end
end
