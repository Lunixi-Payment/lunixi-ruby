# frozen_string_literal: true

module Lunixi
  # One page of a list. next_cursor is opaque: pass it back unchanged as cursor: (page_token: for the
  # subscription, plan, customer, card and invoice lists), or use the iterate methods. total_count is nil
  # unless the list counts rows; page_size is the page size of a subscription list (nil elsewhere). raw is
  # the envelope's data.
  ListPage = Struct.new(:items, :next_cursor, :has_more, :total_count, :raw, :page_size, keyword_init: true) do
    def has_more? # rubocop:disable Naming/PredicatePrefix -- public ListPage API (README)
      has_more == true
    end
  end

  # Answer reading shared by the route-table clients: the envelope's data, list pages (ListPage) and
  # iteration over every page. Not a public API.
  module RouteResponse
    module_function

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
      ListPage.new(items: rows.grep(Hash), next_cursor: token, has_more: has_more, total_count: total, raw: data)
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
      response.except('data').merge(data)
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

          query = query.reject { |key, _| RouteRequest.camel(key.to_s) == RouteRequest.camel(cursor_key.to_s) }.merge(cursor_key => page.next_cursor)
        end
      end
      return items unless block

      items.each(&block)
      nil
    end
  end
end
