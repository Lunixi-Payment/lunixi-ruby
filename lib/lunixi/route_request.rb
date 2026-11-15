# frozen_string_literal: true

module Lunixi
  # Request plumbing shared by the route-table clients (Wallet, Sanction, bank-connect transfers and
  # FX, and the RouteTable products: subscriptions, KYC, identity, marketplace) and the bank-connect and
  # insurance clients: route descriptions in the shared catalog's shape, wire keys, path segments and
  # query values. Single values are checked by RouteValue; answers and pages are read by RouteResponse.
  # Every check runs before anything is sent and names the field, never its value. Not a public API.
  module RouteRequest
    # Idempotency-Key of the bank-connect and insurance routes: 8–200 printable ASCII characters.
    PRINTABLE_IDEMPOTENCY_KEY = /\A[\x21-\x7E]{8,200}\z/
    PRINTABLE_KEY_ROUTE = %r{\A/api/v1/(?:bank-connect|insurance)(?:[/?]|\z)}

    module_function

    # One route in the shared catalog's shape: method, path and the given fields (idempotency_key:,
    # required:, optional:, any_of:, query:, binary:, screening:) under their wire names.
    def route(method, path, **fields)
      described = { 'method' => method, 'path' => path }
      fields.each { |name, value| described[camel(name.to_s)] = value.is_a?(Array) ? value.dup.freeze : value }
      described.freeze
    end

    # The path template with every :name segment filled from params (trimmed, percent-encoded).
    def path!(template, params)
      template.gsub(/:([A-Za-z]+)/) do
        name = Regexp.last_match(1)
        value = params[name]
        raise ConfigurationError, "#{name} is required." unless value.is_a?(String) && !value.strip.empty?

        PhysicalPosIdentifiers.path_id(value.strip, name)
      end
    end

    # A body with wire keys (String or Symbol, the wire name or its snake_case form); nil values are left
    # out. An unknown key, a key given twice or a missing required field raises ConfigurationError.
    def fields!(value, required, optional, label)
      given = wire_keys!(value, required + optional, label)
      missing = required.reject { |key| present?(given[key]) }
      raise ConfigurationError, "#{label} requires #{missing.join(', ')}." unless missing.empty?

      given
    end

    def wire_keys!(value, allowed, label, kind = 'field')
      raise ConfigurationError, "#{label} must be a Hash." unless value.is_a?(Hash)

      unknown = []
      seen = []
      given = {}
      value.each do |key, entry|
        raise ConfigurationError, "#{label} keys must be strings or symbols." unless key.is_a?(String) || key.is_a?(Symbol)

        name = key.to_s
        wire = allowed.include?(name) ? name : camel(name)
        next unknown << name unless allowed.include?(wire)
        raise ConfigurationError, "#{label} #{kind} '#{wire}' is given twice." if seen.include?(wire)

        seen << wire
        given[wire] = entry unless entry.nil?
      end
      return given if unknown.empty?

      raise ConfigurationError, "Unknown #{label} #{kind}(s): #{unknown.join(', ')}. Allowed: " \
                                "#{allowed.empty? ? 'none' : allowed.join(', ')}. The gateway rejects unknown #{kind}s with 400."
    end

    # Query parameters checked against the route's list; nil and '' are left out. Values are Strings,
    # Integers or booleans.
    def query!(filters, allowed, label)
      return {} if filters.nil?

      given = wire_keys!(filters, allowed, label, 'filter')
      given.each_with_object({}) do |(key, value), query|
        next if value == ''
        unless value.is_a?(String) || value.is_a?(Integer) || value == true || value == false
          raise ConfigurationError, "#{label} filter '#{key}' must be a string, an integer or a boolean."
        end

        query[key] = value
      end
    end

    def printable_idempotency_key!(key)
      unless key.is_a?(String) && key.match?(PRINTABLE_IDEMPOTENCY_KEY)
        raise ConfigurationError, 'The Idempotency-Key must be 8–200 printable ASCII characters without spaces; it is sent ' \
                                  'exactly as given. Reuse the same key when retrying the same operation.'
      end

      key
    end

    def present?(value)
      !(value.nil? || value == '' || (value.is_a?(Array) && value.empty?))
    end

    def compact(hash)
      hash.compact
    end

    def camel(name)
      name.gsub(/_([a-z0-9])/) { Regexp.last_match(1).upcase }
    end

    # A Hash with String wire keys (a snake_case key is sent camelCase); nil values are left out. Nested
    # values are sent as given. A key given twice raises ConfigurationError.
    def wire_hash!(value, label)
      value = value.to_h if !value.is_a?(Hash) && value.respond_to?(:to_h) && !value.is_a?(Array) && !value.nil?
      raise ConfigurationError, "#{label} must be a Hash." unless value.is_a?(Hash)

      value.each_with_object({}) do |(key, entry), plain|
        raise ConfigurationError, "#{label} keys must be strings or symbols." unless key.is_a?(String) || key.is_a?(Symbol)

        wire = camel(key.to_s)
        raise ConfigurationError, "#{label} field '#{wire}' is given twice." if plain.key?(wire)

        plain[wire] = entry unless entry.nil?
      end
    end
  end
end
