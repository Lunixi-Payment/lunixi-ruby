# frozen_string_literal: true

class FakePayments
  attr_reader :intents, :reads
  attr_accessor :payment, :failure, :settlement, :checkout_response

  def initialize
    @intents = []
    @reads = []
    @settlement = { 'capturedAmount' => '10050', 'refundedAmount' => '0' }
  end

  def create_intent(body, idempotency_key:)
    @intents << [body, idempotency_key]
    raise Lunixi::TransportError, 'synthetic connection failure' if @failure

    { 'data' => @checkout_response || { 'token' => 'checkout_TOKEN_synthetic_123', 'paymentId' => 'intent_123' } }
  end

  def get(id)
    @reads << id
    raise Lunixi::TransportError, 'synthetic connection failure' if @failure

    { 'data' => @payment, 'details' => @settlement }
  end
end
