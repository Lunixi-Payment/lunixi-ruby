# frozen_string_literal: true

module Lunixi
  # Wallet (/api/v1/wallet/*): the merchant, server-to-server surface of the closed-loop wallet.
  #
  # Every call is signed, reads included; the merchant, its programs and its end users come from the
  # signing key. The key needs the WALLET_SERVICE product (403 PRODUCT_NOT_ENABLED otherwise) and the
  # wallet permission of the route (403 WALLET_INSUFFICIENT_SCOPE otherwise): wallet:*:read for reads,
  # wallet:program|enduser|limit|fee:manage for set-up, wallet:operation:intervene to move money inside
  # the wallet, wallet:bank-payout:operate for IBAN transfers and bank withdrawals, wallet:qr:manage,
  # wallet:bulk:create, wallet:bulk:approve and wallet:enduser:kyc-override for the KYC level.
  #
  # Bodies and filters are checked against WALLET_ROUTES before anything is sent: an unknown field, a
  # missing required field, a non-canonical amount (a number or a decimal) or a missing Idempotency-Key
  # raises ConfigurationError. Keys are the wire names (String or Symbol; snake_case works too). Amounts
  # are minor units as digit strings ("12550" = 125.50 TRY). A call that moves money for an end user names
  # that end user (endUserId, buyerEndUserId); the source account must belong to them (404
  # WALLET_NOT_FOUND otherwise).
  #
  # Answers are the envelope's data; lists return a Lunixi::ListPage.
  class Wallet
    attr_reader :programs, :end_users, :wallets, :deposits, :corporate, :fees, :transfers, :withdrawals, :operations, :topups,
                :payments, :qr, :bulk_payouts

    def initialize(client)
      @invoker = WalletInvoker.new(client)
      @programs = WalletPrograms.new(@invoker)
      @end_users = WalletEndUsers.new(@invoker)
      @wallets = WalletAccounts.new(@invoker)
      @deposits = WalletDeposits.new(@invoker)
      @corporate = WalletCorporate.new(@invoker)
      @fees = WalletFees.new(@invoker)
      @transfers = WalletTransfers.new(@invoker)
      @withdrawals = WalletWithdrawals.new(@invoker)
      @operations = WalletOperations.new(@invoker)
      @topups = WalletTopups.new(@invoker)
      @payments = WalletPayments.new(@invoker)
      @qr = WalletQr.new(@invoker)
      @bulk_payouts = WalletBulkPayouts.new(@invoker)
    end

    # Checks that the key reaches the wallet (signature, product, a wallet:*:manage permission).
    def ping
      @invoker.data('ping')
    end

    def inspect
      '#<Lunixi::Wallet>'
    end
  end

  # Sends one route of WALLET_ROUTES, signed, after checking the path segments, the body (field list,
  # amounts, nested rows), the filters and the Idempotency-Key rule. Not a public API.
  class WalletInvoker
    ROUTE = %r{\A/api/v1/wallet(?:[/?]|\z)}
    QR_IMAGE_ACCEPT = 'image/svg+xml, image/png, application/json'
    CONTROL_CHARACTERS = /[\x00-\x1f\x7f]/

    # The Idempotency-Key of a wallet route: 1–128 characters without control characters, trimmed (the
    # gateway trims the header too).
    def self.idempotency_key!(key, operation = nil)
      value = key.is_a?(String) ? key.strip : ''
      if value.empty?
        raise ConfigurationError, "A stable Idempotency-Key is required#{" for #{operation}" if operation}. Reuse the same key when " \
                                  'retrying the same operation.'
      end
      if value.length > WALLET_IDEMPOTENCY_KEY_MAX || value.match?(CONTROL_CHARACTERS)
        raise ConfigurationError, "The Idempotency-Key must be 1-#{WALLET_IDEMPOTENCY_KEY_MAX} characters without control characters."
      end

      value
    end

    # Minor units only: a positive canonical digit string of at most 18 digits. A number or a decimal is
    # refused, never rounded.
    def self.amount!(value, field)
      return value if value.is_a?(String) && value.match?(WALLET_AMOUNT_PATTERN) && value.match?(/\A[1-9]/)

      raise ConfigurationError, "'#{field}' must be minor units as a digit string (e.g. \"12550\" for 125.50), not a number."
    end

    def initialize(client)
      @client = client
    end

    # The raw answer of one route. params: path segments by name; body: the request Hash; query: filters.
    def call(name, params: {}, body: nil, query: nil, idempotency_key: nil)
      route = WALLET_ROUTES.fetch(name)
      path = RouteRequest.path!(route['path'], params)
      filters = RouteRequest.query!(query, route['query'] || [], name)
      payload = body_for(name, route, body)
      key = key_for(name, route, idempotency_key)
      binary = route['binary'] == true
      @client.request(route['method'], path, body: payload, query: filters, idempotency_key: key, binary: binary,
                                             accept: binary ? QR_IMAGE_ACCEPT : Client::ACCEPT_JSON)
    end

    def data(name, **)
      RouteResponse.unwrap(call(name, **))
    end

    def page(name, **)
      RouteResponse.page(call(name, **))
    end

    # The complete routes require operationId in the body as well; the path wins on the server.
    def with_operation_id(name, operation_id, request)
      route = WALLET_ROUTES.fetch(name)
      given = RouteRequest.wire_keys!(request || {}, route['required'] + route['optional'], name)
      if given.key?('operationId') && given['operationId'] != operation_id
        raise ConfigurationError, 'operationId in the body must match the operation being completed.'
      end

      given.merge('operationId' => operation_id)
    end

    private

    def body_for(name, route, body)
      unless route.key?('required') || route.key?('optional')
        raise ConfigurationError, "#{name} takes no body." unless body.nil? || body == {}

        return nil
      end

      plain = RouteRequest.fields!(body || {}, route['required'] || [], route['optional'] || [], name)
      plain.keys.each do |field|
        plain[field] = self.class.amount!(plain[field], "#{name}.#{field}") if WALLET_AMOUNT_FIELDS.include?(field)
        nested = WALLET_NESTED_FIELDS["#{name}.#{field}"]
        plain[field] = rows!(plain[field], nested, "#{name}.#{field}") if nested
      end
      plain
    end

    def rows!(rows, spec, label)
      raise ConfigurationError, "'#{label}' must be a non-empty array." unless rows.is_a?(Array) && !rows.empty?

      rows.each_with_index.map do |row, index|
        path = "#{label}[#{index}]"
        plain = RouteRequest.fields!(row, spec['required'], spec['optional'], path)
        plain['amount'] = self.class.amount!(plain['amount'], "#{path}.amount") if plain.key?('amount')
        plain
      end
    end

    def key_for(name, route, key)
      return self.class.idempotency_key!(key, name) if route['idempotencyKey']
      raise ConfigurationError, "#{name} does not take an Idempotency-Key." unless key.nil?

      nil
    end
  end
end
