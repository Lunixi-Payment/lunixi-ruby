# frozen_string_literal: true

module Lunixi
  # Explicit payment routes. The advanced Client#request method covers other
  # documented endpoints without pretending to validate their entire DTO schema.
  class Payments
    BASE = '/api/v1/payments'
    attr_reader :client

    def initialize(client)
      @client = client
    end

    # Create hosted/embedded checkout using integer minor units and a durable attempt key.
    # @return [Hash] Unmodified gateway response envelope; creation is not settlement.
    def create_intent(body, idempotency_key:)
      body = payment_body!(body)
      raise ConfigurationError, 'Intent installments are selected in the checkout form' if body.key?('installment')

      client.request('POST', "#{BASE}/intents", body: body, idempotency_key: Client.idempotency_key!(idempotency_key))
    end

    # @return [Hash] Authenticated payment status envelope for reconciliation.
    def get(payment_id)
      client.request('GET', "#{BASE}/#{identifier!(payment_id)}", signed: false)
    end

    # @param filters [Hash] Documented gateway payment list query fields.
    def list(**filters)
      client.request('GET', BASE, query: filters, signed: false)
    end

    # Return merchant-enabled methods; the shared Lunixi form owns the final available list.
    def methods(payment_method: nil)
      query = payment_method ? { paymentMethod: payment_method } : {}
      client.request('GET', "#{BASE}/methods", query: query)
    end

    # Capture an authorization; nil amount requests the gateway's remaining amount.
    def capture(payment_id, idempotency_key:, amount: nil)
      body = { 'paymentIntentId' => identifier!(payment_id) }
      body['amount'] = minor!(amount) unless amount.nil?
      client.request('POST', "#{BASE}/#{payment_id}/capture", body: body, idempotency_key: Client.idempotency_key!(idempotency_key))
    end

    # Refund captured funds; persist a separate key for each refund operation.
    def refund(payment_id, idempotency_key:, amount: nil, reason: nil)
      body = { 'paymentIntentId' => identifier!(payment_id) }
      body['amount'] = minor!(amount) unless amount.nil?
      body['reason'] = reason!(reason) unless reason.nil?
      client.request('POST', "#{BASE}/#{payment_id}/refund", body: body, idempotency_key: Client.idempotency_key!(idempotency_key))
    end

    # Void an authorization without inventing a settlement success result.
    def void(payment_id, idempotency_key:)
      client.request('POST', "#{BASE}/#{identifier!(payment_id)}/void", idempotency_key: Client.idempotency_key!(idempotency_key))
    end

    # Start a 1–5 leg split payment; running statuses are returned, never marked paid.
    def split(body, idempotency_key:)
      data = normalize!(body)
      minor!(data['totalAmount'])
      currency!(data['currency'])
      text!(data['ownerRef'])
      legs = data['legs']
      raise ConfigurationError, 'Split payment requires 1–5 legs' unless legs.is_a?(Array) && legs.size.between?(1, 5)

      total = legs.sum do |leg|
        raise ConfigurationError, 'Split legs must be objects' unless leg.is_a?(Hash)

        minor!(leg['amount'])
      end
      raise ConfigurationError, 'Split leg amounts must equal totalAmount' unless total == data['totalAmount']

      client.request('POST', "#{BASE}/split", body: data, idempotency_key: Client.idempotency_key!(idempotency_key))
    end

    # @return [Hash] Current split-session status envelope.
    def get_split(split_id)
      client.request('GET', "#{BASE}/split/#{identifier!(split_id)}", signed: false)
    end

    # Refund a split session using the documented partial/full amount in minor units.
    def refund_split(split_id, amount:, idempotency_key:, reason: nil)
      body = { 'amount' => minor!(amount) }
      body['reason'] = reason!(reason) unless reason.nil?
      client.request('POST', "#{BASE}/split/#{identifier!(split_id)}/refund", body: body,
                                                                              idempotency_key: Client.idempotency_key!(idempotency_key))
    end

    private

    def identifier!(value)
      raise ConfigurationError, 'Invalid resource identifier' unless value.is_a?(String) && value.match?(/\A[a-zA-Z0-9_-]{1,256}\z/)

      value
    end

    def minor!(value)
      unless value.is_a?(Integer) && value.positive? && value <= JsonBody::MAX_SAFE_INTEGER
        raise ConfigurationError, 'Amount must be a positive safe integer in minor units'
      end

      value
    end

    def currency!(value)
      raise ConfigurationError, 'Currency must be a three-letter uppercase code' unless value.is_a?(String) && value.match?(/\A[A-Z]{3}\z/)
    end

    def reason!(value)
      raise ConfigurationError, 'Reason must be a string of at most 500 characters' unless value.is_a?(String) && value.size <= 500

      value
    end

    def text!(value)
      unless value.is_a?(String) && !value.strip.empty? && value.bytesize <= 255 && !value.match?(/[\x00-\x1f\x7f]/)
        raise ConfigurationError, 'Reference must be a bounded nonempty string'
      end

      value
    end

    def normalize!(body)
      raise ConfigurationError, 'Payment body must be an object' unless body.is_a?(Hash)

      JSON.parse(JsonBody.dump(body))
    end

    def payment_body!(body)
      data = normalize!(body)
      raise ConfigurationError, 'Removed amount field; use amount in integer minor units' if %w[price paidPrice].any? { |key| data.key?(key) }

      minor!(data['amount'])
      currency!(data['currency'])
      text!(data['orderId'])
      validate_callback!(data['callbackUrl']) if data.key?('callbackUrl')
      raise ConfigurationError, 'preauth must be a JSON boolean' if data.key?('preauth') && ![true, false].include?(data['preauth'])

      validate_basket!(data['basketItems'], data['amount']) if data.key?('basketItems')
      data
    end

    def validate_callback!(url)
      uri = URI.parse(url)
      raise ConfigurationError, 'callbackUrl must use HTTPS' unless uri.is_a?(URI::HTTPS) && uri.host && !uri.userinfo && !uri.fragment && url.bytesize <= 2048
    rescue URI::InvalidURIError, TypeError
      raise ConfigurationError, 'Invalid callbackUrl', cause: nil
    end

    def validate_basket!(items, amount)
      raise ConfigurationError, 'basketItems must be a nonempty array' unless items.is_a?(Array) && !items.empty?

      total = items.sum do |item|
        raise ConfigurationError, 'Basket items must be objects' unless item.is_a?(Hash)

        minor!(item['price'])
      end
      raise ConfigurationError, 'Basket total must equal amount' unless total == amount
    end
  end
end
