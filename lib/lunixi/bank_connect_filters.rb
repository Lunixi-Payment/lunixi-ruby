# frozen_string_literal: true

module Lunixi
  # Local checks of the bank-connect read filters (BANK_CONNECT_FILTERS) and of the transfer and FX list
  # filters (BANK_TRANSFER_ROUTES query lists). Not a public API.
  module BankConnectFilters
    DAY_SECONDS = 24 * 60 * 60
    AMOUNT_FILTERS = %w[minAmountMinor maxAmountMinor].freeze

    module_function

    # The query of a read route: unknown filters, values outside their set, limit outside 1–100, more
    # than 100 account ids, a malformed amount or date window raise ConfigurationError. nil, '' and []
    # are left out; a list (status of connections, canonicalType, accountId) is sent comma-separated.
    def read_query!(filters, route)
      given = RouteRequest.wire_keys!(filters || {}, BANK_CONNECT_FILTERS.fetch(route), 'bank-connect', 'filter')
      query = given.each_with_object({}) do |(key, value), out|
        out[key] = read_value(key, value, route) if RouteRequest.present?(value)
      end
      check_transaction_window!(query) if route == 'listTransactions'
      query
    end

    # The query of listTransfers / listFxOrders.
    def transfer_query!(filters, route)
      given = RouteRequest.wire_keys!(filters || {}, BANK_TRANSFER_ROUTES.fetch(route)['query'], 'bank-connect transfer', 'filter')
      given.each_with_object({}) do |(key, value), out|
        out[key] = transfer_value(key, value, route) if RouteRequest.present?(value)
      end
    end

    def read_value(key, value, route)
      case key
      when 'limit', 'cursor' then page_value(key, value)
      when 'status' then route == 'listAccounts' ? one_of(key, value, BankAccountStatus::ALL) : list_of(key, value, BankConnectionStatus::ALL)
      when 'direction' then one_of(key, value, BankTransactionDirection::ALL)
      when 'canonicalType' then list_of(key, value, BankTransactionType::ALL)
      when 'accountId' then account_ids(value)
      when 'bankId', 'connectionId' then RouteRequest.text!(value, key)
      when 'currency' then RouteRequest.currency!(value, key)
      when 'bookedFrom', 'bookedTo' then RouteRequest.iso_time!(value, key)
      else amount(key, value)
      end
    end

    def transfer_value(key, value, route)
      case key
      when 'limit', 'cursor' then page_value(key, value)
      when 'status' then list_of(key, value, route == 'listFxOrders' ? BankFxOrderStatus::ALL : BankTransferStatus::ALL)
      when 'accountId' then RouteRequest.text!(value, key)
      else RouteRequest.iso_time!(value, key)
      end
    end

    def page_value(key, value)
      if key == 'limit'
        unless value.is_a?(Integer) && value.between?(1, BANK_CONNECT_MAX_LIMIT)
          raise ConfigurationError, "'limit' must be an integer from 1 to #{BANK_CONNECT_MAX_LIMIT}."
        end
      elsif !value.is_a?(String) || value.length > BANK_CONNECT_CURSOR_MAX_LENGTH
        raise ConfigurationError, "'cursor' must be the next_cursor of the previous page, passed back unchanged."
      end
      value
    end

    def one_of(key, value, allowed)
      raise ConfigurationError, "'#{key}' must be one of #{allowed.join(', ')}." unless value.is_a?(String) && allowed.include?(value)

      value
    end

    def list_of(key, value, allowed)
      Array(value).each { |entry| one_of(key, entry, allowed) }.join(',')
    end

    def account_ids(value)
      ids = Array(value)
      if ids.length > BANK_CONNECT_MAX_ACCOUNT_FILTER
        raise ConfigurationError, "'accountId' takes at most #{BANK_CONNECT_MAX_ACCOUNT_FILTER} account ids."
      end

      ids.map do |id|
        raise ConfigurationError, "'accountId' must be account ids (strings without commas)." unless id.is_a?(String) && !id.strip.empty? && !id.include?(',')

        id.strip
      end.join(',')
    end

    # Amount filters are inclusive canonical minor-unit strings ("0" allowed).
    def amount(key, value)
      Money.minor(value, positive: false)
    rescue ConfigurationError
      raise ConfigurationError, "'#{key}' must be a canonical minor-unit string such as \"10000\" (not a number).", cause: nil
    end

    # bookedTo needs bookedFrom; when both are readable bookedFrom <= bookedTo and at most 92 days apart;
    # minAmountMinor <= maxAmountMinor.
    def check_transaction_window!(query)
      raise ConfigurationError, "'bookedTo' needs 'bookedFrom': a window without a start is unbounded." if query.key?('bookedTo') && !query.key?('bookedFrom')

      from = RouteRequest.instant(query['bookedFrom'])
      to = RouteRequest.instant(query['bookedTo'])
      if from && to
        raise ConfigurationError, "'bookedFrom' must not be after 'bookedTo'." if from > to
        if to - from > BANK_CONNECT_BOOKED_RANGE_MAX_DAYS * DAY_SECONDS
          raise ConfigurationError, "'bookedFrom' and 'bookedTo' may be at most #{BANK_CONNECT_BOOKED_RANGE_MAX_DAYS} days apart. " \
                                    'Page through narrower windows.'
        end
      end
      return unless query.key?('minAmountMinor') && query.key?('maxAmountMinor')
      return unless query['minAmountMinor'].to_i > query['maxAmountMinor'].to_i

      raise ConfigurationError, "'minAmountMinor' must not be greater than 'maxAmountMinor'."
    end
  end
end
