# frozen_string_literal: true

require 'securerandom'

module Lunixi
  # Bank accounts (/api/v1/bank-connect, product BANK_CONNECT): your connected bank accounts, balances
  # and transactions.
  #
  # Every call is signed, reads included (an unsigned request is 401 AUTH_HEADERS_MISSING). Scopes:
  # bank-connect:view for banks, connections, accounts and request_sync; bank-connect:transactions:view
  # for balances and transactions. The key decides the environment: a TEST key reads only test accounts,
  # a LIVE key only live ones. Connecting a bank and entering bank credentials happen in the Lunixi
  # dashboard only; another organisation's or environment's record is 404 like a missing one.
  #
  # Filters are checked before anything is sent (BANK_CONNECT_FILTERS): an unknown filter, a value
  # outside its set, limit outside 1–100, more than 100 account ids, a malformed amount or a bad date
  # window raises ConfigurationError. Filter keys are the wire names (snake_case works too).
  #
  # Money movement is on transfers (Lunixi::BankConnectTransfers) and fx (Lunixi::BankConnectFx), for a
  # connection whose capabilities include OUTGOING_TRANSFER / FX_EXCHANGE.
  #
  # Answers are the envelope's data; lists return a Lunixi::ListPage.
  class BankConnect
    BASE = '/api/v1/bank-connect'
    attr_reader :transfers, :fx

    def initialize(client, max_retries:, backoff:)
      @client = client
      invoker = BankTransferInvoker.new(client, max_retries: max_retries, backoff: backoff)
      @transfers = BankConnectTransfers.new(invoker)
      @fx = BankConnectFx.new(invoker)
    end

    # The bank catalogue: whether each bank can be connected and what is read from it.
    def list_banks(**filters)
      page('/banks', 'listBanks', filters)
    end

    def iterate_banks(**filters, &block)
      RouteResponse.each_item(filters, block) { |query| list_banks(**query) }
    end

    # Your bank connections, newest first. status takes one value or an Array.
    def list_connections(**filters)
      page('/connections', 'listConnections', filters)
    end

    def iterate_connections(**filters, &block)
      RouteResponse.each_item(filters, block) { |query| list_connections(**query) }
    end

    # 404 bank_connect.connection.not_found for an unknown connection.
    def get_connection(connection_id)
      read("/connections/#{segment(connection_id, 'connectionId')}")
    end

    # Your connected accounts, newest first, each with its data freshness.
    def list_accounts(**filters)
      page('/accounts', 'listAccounts', filters)
    end

    def iterate_accounts(**filters, &block)
      RouteResponse.each_item(filters, block) { |query| list_accounts(**query) }
    end

    # 404 bank_connect.account.not_found for an unknown account.
    def get_account(account_id)
      read("/accounts/#{segment(account_id, 'accountId')}")
    end

    # Asks for a fresh read of the account from the bank (HTTP 202). It never reads earlier than the
    # bank's minimum interval: the answer is then SCHEDULED with scheduledAt, and a request while one is
    # waiting joins it. Nothing is written, so no Idempotency-Key. New transactions arrive by the
    # bank_account.transaction.received webhook. 409 bank_connect.connection.not_active when the
    # connection is not ACTIVE or DEGRADED; 429 RATE_LIMITED (RateLimitError, retry_after in seconds).
    def request_sync(account_id)
      RouteResponse.unwrap(@client.request('POST', "#{BASE}/accounts/#{segment(account_id, 'accountId')}/sync"))
    end

    # The latest balance of each account (bank-connect:transactions:view). Without accountId, every active
    # account of the key's environment.
    def list_balances(**filters)
      page('/balances', 'listBalances', filters)
    end

    def iterate_balances(**filters, &block)
      RouteResponse.each_item(filters, block) { |query| list_balances(**query) }
    end

    # Transactions, newest recorded first (receivedAt, which never changes, so paging forward never
    # skips a transaction that arrives late with an older bank date). bookedFrom (inclusive) / bookedTo
    # (exclusive) filter on the bank date: a Time or an ISO 8601 string with a time zone, at most 92 days
    # apart; bookedTo needs bookedFrom (bookedFrom alone runs up to now). minAmountMinor / maxAmountMinor
    # are inclusive minor-unit strings.
    def list_transactions(**filters)
      page('/transactions', 'listTransactions', filters)
    end

    def iterate_transactions(**filters, &block)
      RouteResponse.each_item(filters, block) { |query| list_transactions(**query) }
    end

    # One transaction with its detail fields (balanceAfterMinor, documentNo, bank).
    def get_transaction(transaction_id)
      read("/transactions/#{segment(transaction_id, 'transactionId')}")
    end

    def inspect
      '#<Lunixi::BankConnect>'
    end

    private

    def page(path, route, filters)
      RouteResponse.page(@client.request('GET', BASE + path, query: BankConnectFilters.read_query!(filters, route)))
    end

    def read(path)
      RouteResponse.unwrap(@client.request('GET', BASE + path))
    end

    def segment(value, field)
      RouteRequest.path!(":#{field}", field => value)
    end
  end

  # bank_connect.transfers: outgoing transfers from a connected account (/api/v1/bank-connect/transfers).
  #
  # Every route, reads included, is signed and needs bank-connect:transfer; the key must have an IP
  # allowlist and the request must come from a listed IP (403 bank_connect.auth.ip_allowlist_required /
  # ip_not_allowed). With an API key there is no e-mail code: create answers SUBMITTED and the transfer
  # is queued for the bank. Follow it with get or the bank_transfer.* webhooks. The bank chooses the rail;
  # Lunixi does not check the balance.
  class BankConnectTransfers
    def initialize(invoker)
      @invoker = invoker
    end

    # Payment purpose codes the bank accepts on this connection: { items: [{ code, name, order }] }. Pass
    # one as paymentPurpose to create; leave it out for the bank's default.
    def list_purposes(connection_id)
      @invoker.data('listTransferPurposes', query: { 'connectionId' => RouteValue.text!(connection_id, 'connectionId') })
    end

    # Creates an outgoing transfer (HTTP 201): { transfer, stepUp, replayed }. request: accountId,
    # receiverIban (TR IBAN, at most 42 characters), receiverName (2–140 characters), amountMinor (a
    # positive minor-unit string: "150075" = 1,500.75 TRY), optional currency, paymentPurpose and
    # description (at most 140 characters).
    #
    # idempotency_key (8–200 printable ASCII) is generated (UUID v4) when nil; a network error or a 5xx
    # is retried with the same key and body. Keep your own key (e.g. your payout id) to retry safely
    # across processes: the same key and body answer the existing transfer with replayed: true, another
    # body is 409 bank_connect.transfer.idempotency_conflict. The key used is in transfer.idempotencyKey
    # and on ApiError#idempotency_key.
    def create(request, idempotency_key: nil)
      body = @invoker.body!('createTransfer', request)
      BankTransferInvoker.check_transfer!(body)
      @invoker.keyed('createTransfer', body, idempotency_key)
    end

    # Transfers, newest first. Filters: accountId, status (one or an Array of BankTransferStatus),
    # createdFrom (inclusive) / createdTo (exclusive) as a Time or an ISO 8601 string, limit 1–100, cursor.
    def list(**filters)
      @invoker.page('listTransfers', query: BankConnectFilters.transfer_query!(filters, 'listTransfers'))
    end

    def iterate(**filters, &block)
      RouteResponse.each_item(filters, block) { |query| list(**query) }
    end

    # 404 bank_connect.transfer.not_found for an unknown id.
    def get(transfer_id)
      @invoker.data('getTransfer', params: { 'transferId' => transfer_id })
    end

    def inspect
      '#<Lunixi::BankConnectTransfers>'
    end
  end

  # bank_connect.fx: currency exchange between two active accounts of one connection in different
  # currencies (/api/v1/bank-connect/fx). Same scope and IP allowlist rule as transfers.
  #
  # Flow: list_rates (optional), create_quote, then create_order with the quote id before
  # quote.expiresAt (the bank sets the validity; see validForSeconds). The order is SUBMITTED and queued;
  # follow it with get_order. Exchange orders have no webhook.
  class BankConnectFx
    def initialize(invoker)
      @invoker = invoker
    end

    # Current rates on the connection: { items, refreshSeconds, fetchedAt }; rates are decimal strings.
    def list_rates(connection_id)
      @invoker.data('listFxRates', query: { 'connectionId' => RouteValue.text!(connection_id, 'connectionId') })
    end

    # Quotes an exchange (HTTP 201). request: sourceAccountId (you sell from it), targetAccountId (you buy
    # into it) and exactly one of sourceAmountMinor / targetAmountMinor (a positive minor-unit string of
    # that account's currency). Nothing is booked; a quote is used by one order.
    def create_quote(request)
      body = @invoker.body!('createFxQuote', request)
      if body.key?('sourceAmountMinor') == body.key?('targetAmountMinor')
        raise ConfigurationError, 'createFxQuote takes exactly one of sourceAmountMinor and targetAmountMinor.'
      end
      raise ConfigurationError, 'createFxQuote needs two different accounts.' if body['sourceAccountId'] == body['targetAccountId']

      @invoker.post('createFxQuote', body)
    end

    # Executes a quote (HTTP 201): { order, replayed }. request: quoteId, optional description (at most
    # 140 characters). idempotency_key follows the rule of transfers.create and is generated when nil.
    # 409 bank_connect.fx.quote_expired / quote_used: ask for a new quote.
    def create_order(request, idempotency_key: nil)
      body = @invoker.body!('createFxOrder', request)
      BankTransferInvoker.check_description!(body['description']) if body.key?('description')
      @invoker.keyed('createFxOrder', body, idempotency_key)
    end

    # Exchange orders, newest first. Filters: status (one or an Array of BankFxOrderStatus), limit, cursor.
    def list_orders(**filters)
      @invoker.page('listFxOrders', query: BankConnectFilters.transfer_query!(filters, 'listFxOrders'))
    end

    def iterate_orders(**filters, &block)
      RouteResponse.each_item(filters, block) { |query| list_orders(**query) }
    end

    # 404 bank_connect.fx.order_not_found for an unknown id.
    def get_order(order_id)
      @invoker.data('getFxOrder', params: { 'orderId' => order_id })
    end

    def inspect
      '#<Lunixi::BankConnectFx>'
    end
  end

  # Sends one route of BANK_TRANSFER_ROUTES, signed. The keyed writes (createTransfer, createFxOrder)
  # take the caller's key (checked) or a new UUID v4, and are retried with the same key and body after
  # a network error or a 5xx. Not a public API.
  class BankTransferInvoker
    def self.check_transfer!(body)
      raise ConfigurationError, "'receiverIban' must be at most #{BANK_TRANSFER_IBAN_MAX} characters." if body['receiverIban'].length > BANK_TRANSFER_IBAN_MAX
      unless body['receiverName'].length.between?(BANK_TRANSFER_RECEIVER_NAME_MIN, BANK_TRANSFER_RECEIVER_NAME_MAX)
        raise ConfigurationError, "'receiverName' must be #{BANK_TRANSFER_RECEIVER_NAME_MIN}-#{BANK_TRANSFER_RECEIVER_NAME_MAX} characters."
      end

      body['currency'] = RouteValue.currency!(body['currency'], 'currency') if body.key?('currency')
      if body.key?('paymentPurpose') && !(body['paymentPurpose'].is_a?(String) && body['paymentPurpose'].match?(BANK_TRANSFER_PAYMENT_PURPOSE_PATTERN))
        raise ConfigurationError, "'paymentPurpose' must be a code from list_purposes (letters, digits, underscore; at most 64)."
      end

      check_description!(body['description']) if body.key?('description')
      body
    end

    def self.check_description!(value)
      return if value.is_a?(String) && value.length <= BANK_TRANSFER_DESCRIPTION_MAX

      raise ConfigurationError, "'description' must be a string of at most #{BANK_TRANSFER_DESCRIPTION_MAX} characters."
    end

    # The caller's key (checked) or a new UUID v4 for nil / ''.
    def self.idempotency_key_for(key)
      return SecureRandom.uuid if key.nil? || key == ''

      RouteRequest.printable_idempotency_key!(key)
    end

    def initialize(client, max_retries:, backoff:)
      @client = client
      @max_retries = max_retries
      @backoff = backoff
    end

    # The body of a write route: unknown or missing fields fail before sending; nil and '' are left out;
    # amounts are positive canonical minor-unit strings; other required fields non-empty strings (trimmed).
    def body!(name, request)
      route = BANK_TRANSFER_ROUTES.fetch(name)
      given = RouteRequest.wire_keys!(request, route['required'] + route['optional'], name)
      body = given.reject { |_, value| value == '' }
      body.each_key { |key| body[key] = amount!(key, body[key]) if BANK_TRANSFER_AMOUNT_FIELDS.include?(key) }
      missing = route['required'].reject { |key| body.key?(key) }
      raise ConfigurationError, "#{name} requires #{missing.join(', ')}." unless missing.empty?

      route['required'].each { |key| body[key] = RouteValue.text!(body[key], key) unless BANK_TRANSFER_AMOUNT_FIELDS.include?(key) }
      body
    end

    def data(name, params: {}, query: {})
      route = BANK_TRANSFER_ROUTES.fetch(name)
      RouteResponse.unwrap(@client.request(route['method'], RouteRequest.path!(route['path'], params), query: query))
    end

    def page(name, query:)
      route = BANK_TRANSFER_ROUTES.fetch(name)
      RouteResponse.page(@client.request(route['method'], route['path'], query: query))
    end

    def post(name, body)
      RouteResponse.unwrap(@client.request('POST', BANK_TRANSFER_ROUTES.fetch(name)['path'], body: body))
    end

    # 1 + max_retries attempts with the same key and body; a network error or a 5xx is retried, anything
    # else is raised at once. An answered error carries the key as idempotency_key.
    def keyed(name, body, idempotency_key)
      key = self.class.idempotency_key_for(idempotency_key)
      path = BANK_TRANSFER_ROUTES.fetch(name)['path']
      attempt = 0
      begin
        RouteResponse.unwrap(@client.request('POST', path, body: body, idempotency_key: key, max_retries: 0))
      rescue TransportError, ApiError => e
        raise with_key(e, key), cause: nil unless retryable?(e) && attempt < @max_retries

        @backoff.call(attempt)
        attempt += 1
        retry
      end
    end

    private

    def amount!(key, value)
      Money.minor(value, positive: true)
    rescue ConfigurationError
      raise ConfigurationError, "'#{key}' must be a positive canonical minor-unit string such as \"150075\" (not a number).", cause: nil
    end

    def retryable?(error)
      error.is_a?(TransportError) || error.status.to_i >= 500
    end

    def with_key(error, key)
      return error unless error.is_a?(ApiError)

      error.class.new(status: error.status, code: error.code, request_id: error.request_id, retry_after: error.retry_after,
                      details: error.details, idempotency_key: key, message: error.message)
    end
  end
end
