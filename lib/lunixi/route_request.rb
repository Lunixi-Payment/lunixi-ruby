# frozen_string_literal: true

module Lunixi
  # One page of a list. next_cursor is opaque: pass it back unchanged as cursor: (page_token: for the
  # subscription, plan, customer, card and invoice lists), or use the iterate methods. total_count is nil
  # unless the list counts rows; page_size is the page size of a subscription list (nil elsewhere). raw is
  # the envelope's data.
  ListPage = Struct.new(:items, :next_cursor, :has_more, :total_count, :raw, :page_size, keyword_init: true) do
    def has_more?
      has_more == true
    end
  end

  # Request plumbing shared by the route-table clients (Wallet, Sanction, bank-connect transfers and
  # FX, and the RouteTable products: subscriptions, KYC, identity, marketplace) and the bank-connect and
  # insurance clients: route descriptions in the shared catalog's shape,
  # wire keys, path segments, query values, and envelope and page reading. Every check runs before
  # anything is sent and names the field, never its value. Not a public API.
  module RouteRequest
    # Idempotency-Key of the bank-connect and insurance routes: 8–200 printable ASCII characters.
    PRINTABLE_IDEMPOTENCY_KEY = /\A[\x21-\x7E]{8,200}\z/
    PRINTABLE_KEY_ROUTE = %r{\A/api/v1/(?:bank-connect|insurance)(?:[/?]|\z)}
    CURRENCY = /\A[A-Z]{3}\z/

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

        PhysicalPosRequest.path_id(value.strip, name)
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

    # A trimmed non-empty String, at most max characters when given.
    def text!(value, field, max = nil)
      raise ConfigurationError, "'#{field}' is required." unless value.is_a?(String) && !value.strip.empty?

      text = value.strip
      raise ConfigurationError, "'#{field}' must be at most #{max} characters." if max && text.length > max

      text
    end

    def currency!(value, field)
      currency = value.is_a?(String) ? value.strip.upcase : ''
      raise ConfigurationError, "'#{field}' must be an ISO 4217 code such as TRY." unless currency.match?(CURRENCY)

      currency
    end

    # A Time (sent as ISO 8601 UTC) or an ISO 8601 string with a time zone (sent trimmed).
    def iso_time!(value, field)
      return value.getutc.strftime('%Y-%m-%dT%H:%M:%S.%LZ') if value.is_a?(Time)
      return value.strip if value.is_a?(String) && !value.strip.empty?

      raise ConfigurationError, "'#{field}' must be a Time or an ISO 8601 string with a time zone."
    end

    # The instant of a Time or an ISO 8601 string, nil when it cannot be read.
    def instant(value)
      return value if value.is_a?(Time)
      return nil unless value.is_a?(String) && !value.strip.empty?

      Time.iso8601(value.strip)
    rescue ArgumentError
      nil
    end

    def present?(value)
      !(value.nil? || value == '' || (value.is_a?(Array) && value.empty?))
    end

    def compact(hash)
      hash.reject { |_, value| value.nil? }
    end

    def camel(name)
      name.gsub(/_([a-z0-9])/) { Regexp.last_match(1).upcase }
    end

    # The envelope's data (the answer itself when there is none).
    def unwrap(response)
      response.is_a?(Hash) && response.key?('data') ? response['data'] : response
    end

    # A list answer: rows are data (an array), data.items or the first array member of data; paging is
    # the envelope's top-level pageInfo (a copy inside data is read as a fallback) or data.nextCursor.
    def page(response)
      data = unwrap(response)
      container = data.is_a?(Hash) ? data : {}
      info = hash_at(response, 'pageInfo') || hash_at(container, 'pageInfo')
      cursor = text(info && info['nextCursor']) || text(container['nextCursor'])
      has_more = info&.key?('hasMore') ? info['hasMore'] == true && !cursor.nil? : !cursor.nil?
      total = [info && info['totalCount'], container['totalCount']].find { |value| value.is_a?(Integer) }
      ListPage.new(items: data.is_a?(Array) ? data : rows(container), next_cursor: cursor, has_more: has_more, total_count: total, raw: data)
    end

    def rows(container)
      return container['items'] if container['items'].is_a?(Array)

      container.values.find { |value| value.is_a?(Array) } || []
    end

    def hash_at(value, key)
      value[key] if value.is_a?(Hash) && value[key].is_a?(Hash)
    end

    def text(value)
      value.is_a?(String) && !value.empty? ? value : nil
    end

    # A list answer of the RouteTable products: rows are data (an array) or data.items / operations /
    # rows (objects only); the cursor is pageInfo.nextCursor or endCursor (a pageInfo that names neither
    # is the last page), else nextCursor or nextPageToken in data or at the envelope root; total_count is
    # pageInfo.totalCount, data.totalCount or data.total. has_more is pageInfo.hasMore when it is a boolean.
    def cursor_page(response)
      data = unwrap(response)
      container = data.is_a?(Hash) ? data : {}
      root = response.is_a?(Hash) ? response : {}
      rows = data.is_a?(Array) ? data : %w[items operations rows].map { |key| container[key] }.find { |value| value.is_a?(Array) } || []
      info = hash_at(container, 'pageInfo') || hash_at(root, 'pageInfo')
      token = page_token(info, container, root)
      total = [info && info['totalCount'], container['totalCount'], container['total']].find { |value| value.is_a?(Integer) }
      has_more = info && [true, false].include?(info['hasMore']) ? info['hasMore'] : !token.nil?
      ListPage.new(items: rows.select { |row| row.is_a?(Hash) }, next_cursor: token, has_more: has_more, total_count: total, raw: data)
    end

    def page_token(info, container, root)
      if info
        cursor = text(info['nextCursor']) || text(info['endCursor'])
        return cursor if cursor || info.key?('nextCursor') || info.key?('endCursor')
      end
      [container['nextCursor'], container['nextPageToken'], root['nextPageToken'], root['nextCursor']].map { |value| text(value) }.compact.first
    end

    # Answers that put their fields at the envelope root and/or under data: both, merged (data wins).
    def merge_root(response)
      return {} unless response.is_a?(Hash)

      data = response['data'].is_a?(Hash) ? response['data'] : {}
      response.reject { |key, _| key == 'data' }.merge(data)
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

    # nil or '' is nil; anything else must be a String.
    def optional_text(value, field)
      return nil if value.nil? || value == ''
      raise ConfigurationError, "'#{field}' must be a string." unless value.is_a?(String)

      value
    end

    def one_of!(value, allowed, field)
      return value if allowed.include?(value)

      raise ConfigurationError, "'#{field}' must be one of #{allowed.join(', ')}."
    end

    # Every item of every page, fetching the next page only when it is needed. cursor_key is the filter
    # the next cursor goes back in. Without a block it returns an Enumerator.
    def each_item(filters, block, cursor_key = :cursor, &fetch)
      items = Enumerator.new do |yielder|
        query = filters.transform_keys(&:to_sym)
        loop do
          page = fetch.call(query)
          page.items.each { |item| yielder << item }
          break unless page.has_more && page.next_cursor

          query = query.reject { |key, _| camel(key.to_s) == camel(cursor_key.to_s) }.merge(cursor_key => page.next_cursor)
        end
      end
      return items unless block

      items.each(&block)
      nil
    end
  end
end
