# frozen_string_literal: true

module Lunixi
  # One page of a physical POS list. total_count is filled only with includeTotal: true on entity
  # lists; pass next_cursor as cursor: for the next page (or use the iterate_* methods).
  PhysicalPosPage = Struct.new(:items, :has_more, :next_cursor, :total_count, keyword_init: true)

  # Answer of a physical POS write that carries an Idempotency-Key.
  #
  # data is the route's payload unchanged ({ 'payment' => … }, { 'store' => … },
  # { 'device' => …, 'closedAssignment' => … }, { 'run' => … }); result['store'] reads it directly.
  # replayed is true when the same key and body were sent before: the record is then its CURRENT state.
  # status_code is 202 for a new payment, reversal or end-of-day run (accepted, not paid: follow the
  # outcome by webhook or get_payment), 201 for a created record, 200 for a replay, a cancel or a state
  # change. idempotency_key is the key sent; keep it with your order, an uncertain retry must reuse it.
  class PhysicalPosWriteResult
    attr_reader :data, :replayed, :status_code, :idempotency_key

    def initialize(data:, replayed:, status_code:, idempotency_key:)
      @data = data
      @replayed = replayed
      @status_code = status_code
      @idempotency_key = idempotency_key
    end

    def [](name)
      data[name.to_s]
    end

    # The payment of a payment write (for a reversal, the new child payment).
    def payment
      data['payment']
    end

    def replayed?
      replayed
    end

    # True for a newly accepted payment, reversal or end-of-day run (HTTP 202).
    def accepted?
      status_code == 202
    end

    def to_h
      data.merge('replayed' => replayed, 'statusCode' => status_code, 'idempotencyKey' => idempotency_key)
    end

    def inspect
      "#<Lunixi::PhysicalPosWriteResult status_code=#{status_code} replayed=#{replayed}>"
    end
  end
end
