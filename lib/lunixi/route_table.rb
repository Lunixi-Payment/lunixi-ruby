# frozen_string_literal: true

module Lunixi
  # Sends one route of a product route table (SUBSCRIPTION_ROUTES, KYC_ROUTES, IDENTITY_ROUTES,
  # MARKETPLACE_ROUTES). Each route is described in the shared catalog's shape:
  #
  #   method, path       the HTTP method and path template (:name filled from params)
  #   stepUp             sent with the per-request signature; otherwise the access token only
  #   idempotencyKey     'required' | 'optional' | 'none' (the Idempotency-Key header)
  #   required/optional  the body fields; any other field is refused before sending
  #   free               the body is a Hash the gateway validates (no field list)
  #   optionalBody       an empty body is sent as no body
  #   query / anyQuery   the accepted filters; anyQuery accepts any scalar filter
  #
  # Every check runs before anything is sent and raises ConfigurationError naming the field, never its
  # value (card data and document images included). Subscription and marketplace routes carry money:
  # bodies, filters and answers are checked with WireMoney.validate_wire. Not a public API.
  class RouteTable
    MONEY_ROUTE = %r{\A/api/v1/(?:subscriptions|marketplace)(?:/|\z)}
    # Routes whose Idempotency-Key is any non-empty string without control characters (sent trimmed).
    KEY_ROUTE = %r{\A/api/(?:v1/(?:subscriptions|kyc|identity|marketplace)|panel/v1/subscriptions/portal)(?:[/?]|\z)}
    CONTROL_CHARACTERS = /[\x00-\x1f\x7f]/
    KEY_RULES = %w[required optional none].freeze

    def self.idempotency_key!(key, name = nil)
      value = key.is_a?(String) ? key.strip : ''
      if value.empty? || value.match?(CONTROL_CHARACTERS)
        raise ConfigurationError, "The Idempotency-Key#{" of #{name}" if name} must be a non-empty string without control characters."
      end

      value
    end

    # The request's own idempotencyKey or the idempotency_key: argument (both given: they must agree).
    def self.idempotency_key_of(name, request, key)
      own = request.is_a?(Hash) ? request['idempotencyKey'] : nil
      own = own.is_a?(String) && !own.strip.empty? ? own.strip : nil
      given = key.is_a?(String) && !key.strip.empty? ? key.strip : nil
      raise ConfigurationError, "#{name}: the request's idempotencyKey and the idempotency_key: argument differ." if own && given && own != given

      given || own || key
    end

    def initialize(client, routes)
      @client = client
      @routes = routes
    end

    # The raw answer of one route. params: path segments by wire name; query: filters; body: the request
    # Hash (wire names, snake_case works too).
    def call(name, params: {}, query: nil, body: nil, idempotency_key: nil)
      route = @routes.fetch(name) { raise ArgumentError, "Unknown route #{name}." }
      path = RouteRequest.path!(route['path'], params)
      key = key!(name, route['idempotencyKey'] || 'none', idempotency_key)
      filters = query.nil? ? {} : filters!(name, route, query)
      payload = body!(name, route, body)
      money = path.match?(MONEY_ROUTE)
      if money
        WireMoney.validate_wire(payload)
        WireMoney.validate_wire(filters)
      end
      response = @client.request(route['method'], path, body: payload, query: filters, idempotency_key: key, signed: route['stepUp'] == true)
      WireMoney.validate_wire(response) if money
      response
    end

    # The envelope's data.
    def data(name, **)
      RouteResponse.unwrap(call(name, **))
    end

    # A Lunixi::ListPage.
    def page(name, **)
      RouteResponse.cursor_page(call(name, **))
    end

    # A subscription list: the cursor is nextPageToken (send it back as page_token:) and page_size the
    # envelope's pageSize (the row count when there is none).
    def token_page(name, **)
      response = call(name, **)
      page = RouteResponse.cursor_page(response)
      size = response.is_a?(Hash) && response['pageSize'].is_a?(Integer) ? response['pageSize'] : page.items.length
      ListPage.new(items: page.items, next_cursor: page.next_cursor, has_more: page.has_more, total_count: page.total_count,
                   raw: page.raw, page_size: size)
    end

    private

    def key!(name, rule, key)
      raise ArgumentError, "Unknown Idempotency-Key rule #{rule}." unless KEY_RULES.include?(rule)

      if key.nil?
        return nil unless rule == 'required'

        raise ConfigurationError, "A stable Idempotency-Key is required for #{name}. Reuse the same key when retrying the same operation."
      end
      raise ConfigurationError, "#{name} does not take an Idempotency-Key." if rule == 'none'

      self.class.idempotency_key!(key, name)
    end

    def filters!(name, route, query)
      return RouteRequest.query!(query, route['query'] || [], name) unless route['anyQuery']

      RouteRequest.wire_hash!(query, "#{name} filters").each_with_object({}) do |(key, value), filters|
        next if value == ''
        unless value.is_a?(String) || value.is_a?(Integer) || value == true || value == false
          raise ConfigurationError, "#{name} filter '#{key}' must be a string, an integer or a boolean."
        end

        filters[key] = value
      end
    end

    def body!(name, route, body)
      if route.key?('required') || route.key?('optional')
        plain = RouteRequest.fields!(body || {}, route['required'] || [], route['optional'] || [], name)
      elsif route['free']
        plain = RouteRequest.wire_hash!(body.nil? && route['optionalBody'] ? {} : body, "#{name} body")
      else
        raise ConfigurationError, "#{name} takes no body." unless body.nil? || body == {}

        return nil
      end
      route['optionalBody'] && plain.empty? ? nil : plain
    end
  end
end
