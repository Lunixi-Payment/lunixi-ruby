# frozen_string_literal: true

module Lunixi
  # Reads physical POS answers (records, pages, keyed write results) and maps gateway errors to the
  # typed physical POS errors.
  module PhysicalPosResponses
    module_function

    def unwrap(response)
      response.is_a?(Hash) && response.key?('data') ? response['data'] : response
    end

    # data[name] of a single-record answer, or data itself when the wrapper is missing.
    def member(response, name)
      data = unwrap(response)
      data.is_a?(Hash) && !data[name].nil? ? data[name] : data
    end

    # Paging from the envelope's top-level pageInfo.
    def page(response)
      payload = unwrap(response)
      items = payload.is_a?(Hash) && payload['items'].is_a?(Array) ? payload['items'] : []
      info = hash_at(response, 'pageInfo') || hash_at(payload, 'pageInfo') || {}
      cursor = info['nextCursor'].is_a?(String) && !info['nextCursor'].empty? ? info['nextCursor'] : nil
      total = info['totalCount'].is_a?(Integer) ? info['totalCount'] : nil
      PhysicalPosPage.new(items: items, has_more: info['hasMore'] == true && !cursor.nil?, next_cursor: cursor, total_count: total)
    end

    def hash_at(value, key)
      value[key] if value.is_a?(Hash) && value[key].is_a?(Hash)
    end

    # Every item of every page, fetching the next page only when it is needed. Without a block it
    # returns an Enumerator.
    def each_item(filters, block, &fetch)
      items = Enumerator.new do |yielder|
        query = filters.transform_keys(&:to_sym)
        loop do
          page = fetch.call(query)
          page.items.each { |item| yielder << item }
          break unless page.has_more && page.next_cursor

          query = query.merge(cursor: page.next_cursor)
        end
      end
      return items unless block

      items.each(&block)
      nil
    end

    # Keyed write answer: the route's data plus replayed, the status code and the key sent.
    def write_result(response, key, fallback)
      data = unwrap(response)
      data = {} unless data.is_a?(Hash)
      replayed = data['replayed'] == true
      PhysicalPosWriteResult.new(data: data, replayed: replayed, status_code: status_code(response, fallback.call(replayed)), idempotency_key: key)
    end

    def status_code(response, fallback)
      value = response.is_a?(Hash) ? response['statusCode'] : nil
      value.is_a?(Integer) && value.between?(200, 299) ? value : fallback
    end

    # Typed physical POS errors for one answered request: card data (field path), void after
    # end-of-day (allowed_operation), 429 (retry_after in seconds). The key of a write is attached.
    def translate(error, key = nil)
      return error unless error.is_a?(ApiError)

      common = { status: error.status, code: error.code, request_id: error.request_id, details: error.details,
                 idempotency_key: key || error.idempotency_key, message: error.message }
      if error.code == PhysicalPosCardDataRejectedError::CODE
        field = error.details['field']
        PhysicalPosCardDataRejectedError.new(field: field.is_a?(String) ? field : nil, retry_after: error.retry_after, **common)
      elsif error.code == PhysicalPosVoidAfterSettlementError::CODE
        allowed = error.details['allowedOperation']
        PhysicalPosVoidAfterSettlementError.new(allowed_operation: allowed.is_a?(String) ? allowed : nil, retry_after: error.retry_after, **common)
      elsif error.status == 429
        PhysicalPosRateLimitError.new(retry_after: retry_after_seconds(error), **common)
      elsif key.nil?
        error
      else
        error.class.new(retry_after: error.retry_after, **common)
      end
    end

    # The Retry-After header in seconds, or details.retryAfterSeconds when the header is missing.
    def retry_after_seconds(error)
      number(error.retry_after) || number(error.details['retryAfterSeconds'])
    end

    def number(value)
      return value if value.is_a?(Integer) || (value.is_a?(Float) && value.finite?)
      return nil unless value.is_a?(String)

      text = value.strip
      return text.to_i if text.match?(/\A\d{1,9}\z/)

      text.match?(/\A\d{1,9}\.\d{1,9}\z/) ? text.to_f : nil
    end
  end
end
