# frozen_string_literal: true

require 'securerandom'
require 'time'

module Lunixi
  # Thread-safe server-side gateway client. Responses retain the gateway envelope.
  class Client
    AUTH_PATH = '/api/v1/auth/token'
    METHODS = %w[GET HEAD POST PUT PATCH DELETE].freeze
    attr_reader :payments, :fraud

    def initialize(base_url:, key_id:, private_key:, timeout: 30, max_retries: 2, transport: nil,
                   clock: -> { Time.now.utc }, sleeper: ->(seconds) { sleep(seconds) }, ca_file: nil)
      @origin = validate_origin(base_url)
      raise ConfigurationError, 'Invalid key id' unless key_id.is_a?(String) && key_id.match?(/\A[a-zA-Z0-9_.:-]{1,200}\z/)
      raise ConfigurationError, 'timeout must be between 1 and 120 seconds' unless timeout.is_a?(Numeric) && timeout.between?(1, 120)
      raise ConfigurationError, 'max_retries must be between 0 and 3' unless max_retries.is_a?(Integer) && max_retries.between?(0, 3)

      @key_id = key_id.dup.freeze
      @signer = Signer.new(private_key)
      @transport = transport || NetHttpTransport.new(timeout: timeout, ca_file: ca_file)
      @max_retries = max_retries
      @clock = clock
      @sleeper = sleeper
      @token_mutex = Mutex.new
      @token = nil
      @token_expires_at = Time.at(0)
      @payments = Payments.new(self)
      @fraud = Fraud.new(self)
    end

    # Advanced, signed transport for other documented gateway surfaces. It does
    # not invent field schemas, interpret financial results or retry an unsafe POST.
    def request(method, path, body: nil, query: {}, idempotency_key: nil, signed: true, binary: false)
      method = method.to_s.upcase
      raise ConfigurationError, 'Unsupported HTTP method' unless METHODS.include?(method)
      raise ConfigurationError, 'GET and HEAD cannot have a body' if %w[GET HEAD].include?(method) && !body.nil?

      path = safe_path(path, query)
      key = self.class.idempotency_key!(idempotency_key) if idempotency_key
      Money.validate_operation_amount(path, body)
      if Money.fiat_route?(path)
        Money.validate_fields(body)
        Money.validate_fields(query)
      end
      bytes = body.nil? ? nil : JsonBody.dump(body)
      raise ConfigurationError, 'Request body exceeds the size limit' if bytes && bytes.bytesize > 1024 * 1024

      perform_request(method, path, bytes, key, signed, binary)
    end

    # Validates caller-owned durable keys; a generated key on every retry is unsafe.
    def self.idempotency_key!(key)
      unless key.is_a?(String) && key.match?(/\A[\x21-\x7e]{16,128}\z/)
        raise ConfigurationError, 'Idempotency key must be 16–128 printable ASCII characters without spaces'
      end

      key.dup.freeze
    end

    def inspect
      '#<Lunixi::Client credentials=[REDACTED]>'
    end

    private

    def perform_request(method, path, bytes, key, signed, binary)
      safe_to_retry = %w[GET HEAD].include?(method) || !key.nil?
      retries = 0
      reauthenticated = false
      loop do
        token = access_token
        response = transmit(method, path, bytes, key, token, signed)
        if response.status == 401 && !reauthenticated && safe_to_retry
          invalidate_token(token)
          reauthenticated = true
          next
        end
        if retryable_response?(response, safe_to_retry, retries)
          pause(retries, response.headers)
          retries += 1
          next
        end
        return decode_response(response, binary: binary, fiat: Money.fiat_route?(path), running_split: method == 'POST' && path == '/api/v1/payments/split')
      rescue TransportError
        raise unless safe_to_retry && retries < @max_retries

        pause(retries, {})
        retries += 1
      end
    end

    def retryable_response?(response, safe_to_retry, retries)
      [429, 502, 503, 504].include?(response.status) && safe_to_retry && retries < @max_retries
    end

    def validate_origin(value)
      uri = URI.parse(value)
      unless uri.is_a?(URI::HTTPS) && uri.host && !uri.userinfo && !uri.query && !uri.fragment && ['', '/'].include?(uri.path)
        raise ConfigurationError, 'base_url must be an HTTPS origin without credentials, path, query or fragment'
      end

      value.delete_suffix('/').freeze
    rescue URI::InvalidURIError, TypeError
      raise ConfigurationError, 'Invalid HTTPS gateway origin', cause: nil
    end

    def safe_path(path, query)
      unless path.is_a?(String) && path.start_with?('/api/v1/') && path.match?(%r{\A/[a-zA-Z0-9_~./%-]+\z})
        raise ConfigurationError, 'Only relative /api/v1/ gateway paths are accepted'
      end

      path.split('/').each do |segment|
        decoded = URI::RFC2396_PARSER.unescape(segment)
        raise ConfigurationError, 'Unsafe gateway path segment' if ['.', '..'].include?(decoded) || decoded.match?(%r{[\\/\x00-\x20\x7f%]})
      end
      encoded = encoded_query(query)
      encoded.empty? ? path : "#{path}?#{encoded}"
    end

    def encoded_query(query)
      raise ConfigurationError, 'Query must be a hash' unless query.is_a?(Hash)

      pairs = query.flat_map do |name, value|
        raise ConfigurationError, 'Invalid query key' unless name.to_s.match?(/\A[a-zA-Z][a-zA-Z0-9_]{0,63}\z/)

        Array(value).map do |entry|
          unless entry.is_a?(String) || entry.is_a?(Integer) || entry == true || entry == false
            raise ConfigurationError, 'Query values must be strings, integers or booleans'
          end
          raise ConfigurationError, 'Query value is too long' if entry.to_s.bytesize > 4096

          [name.to_s, entry.to_s]
        end
      end
      URI.encode_www_form(pairs)
    end

    def signed_headers(method, path, body)
      date = @clock.call.getutc.iso8601
      nonce = SecureRandom.uuid
      digest = Signer.digest(body) unless body.nil?
      headers = { 'X-Key-Id' => @key_id, 'X-Date' => date, 'X-Nonce' => nonce }
      headers['Digest'] = digest if digest
      headers['X-Signature'] = @signer.sign(Signer.canonical(method, path, date, nonce, digest))
      headers
    end

    def transmit(method, path, body, key, token, signed)
      headers = { 'Accept' => 'application/json', 'User-Agent' => "lunixi-sdk-ruby/#{VERSION}" }
      headers['Authorization'] = "Bearer #{token}" if token
      headers['Content-Type'] = 'application/json' unless body.nil?
      headers['Idempotency-Key'] = key if key
      headers.merge!(signed_headers(method, path, body)) if signed
      response = @transport.call(method: method, uri: URI.parse(@origin + path), headers: headers.freeze, body: body)
      unless response.is_a?(Response) && response.status.is_a?(Integer) && response.headers.is_a?(Hash) && response.body.is_a?(String)
        raise TransportError, 'Transport returned an invalid response'
      end
      raise TransportError, 'Gateway response exceeds the size limit' if response.body.bytesize > NetHttpTransport::MAX_RESPONSE_BYTES
      raise RedirectError, 'Gateway redirects are rejected; credentials were not forwarded' if response.status.between?(300, 399)

      response
    end

    def access_token
      @token_mutex.synchronize do
        return @token if @token && @clock.call < @token_expires_at

        response = transmit('POST', AUTH_PATH, nil, nil, nil, true)
        payload = decode_response(response)
        data = payload['data'].is_a?(Hash) ? payload['data'] : payload
        token = data['access_token'] || data['accessToken']
        ttl = data['expires_in'] || data['expiresIn']
        unless token.is_a?(String) && token.match?(/\A[a-zA-Z0-9_.:-]{1,8192}\z/) && ttl.is_a?(Integer) && ttl.positive? && ttl <= 86_400
          raise AuthenticationError.new(status: 502, code: 'invalid_token_response')
        end

        @token = token.freeze
        @token_expires_at = @clock.call + [ttl - 30, 1].max
        token
      end
    end

    def invalidate_token(previous)
      @token_mutex.synchronize { @token = nil if @token == previous }
    end

    def pause(attempt, headers)
      retry_after = headers['retry-after'] || headers['Retry-After']
      seconds = retry_after.to_s.match?(/\A\d{1,3}\z/) ? [retry_after.to_i, 5].min : [0.1 * (2**attempt), 2].min
      @sleeper.call(seconds)
    end

    def response_payload(response)
      payload = response.body.empty? ? {} : JSON.parse(response.body, max_nesting: 64)
      raise ApiError.new(status: response.status, code: 'invalid_json_response') unless payload.is_a?(Hash)

      payload
    rescue JSON::ParserError
      raise ApiError.new(status: response.status, code: 'invalid_json_response'), cause: nil
    end

    def decode_response(response, binary: false, running_split: false, fiat: false)
      return response.body.b.freeze if binary && response.status.between?(200, 299)

      payload = response_payload(response)
      Money.validate_fields(payload, response: true) if fiat
      return payload if response.status.between?(200, 299)

      error_class = case response.status
                    when 401, 403 then AuthenticationError
                    when 400, 422 then ValidationError
                    when 429 then RateLimitError
                    else ApiError
                    end
      error = error_class.new(status: response.status, code: payload['code'],
                              request_id: response.headers['x-request-id'] || response.headers['X-Request-Id'],
                              retry_after: response.headers['retry-after'])
      # Running split sessions are successful protocol responses, not completed payments.
      running = %w[COMPOSING AUTHORIZING AWAITING_3DS AWAITING_ACTION AWAITING_CREDIT_APPROVAL AWAITING_REPLACEMENT_CARD AUTHORIZED CAPTURING]
      return payload if running_split && response.status == 400 && running.include?(payload['code']) && payload.dig('data', 'splitPaymentId').is_a?(String)

      raise error
    end
  end
end
