# frozen_string_literal: true

module Lunixi
  # Body of POST /api/v1/payments/direct/payment (payments.direct_method_payment). amount is the order
  # total as a positive canonical minor-unit string. Choose the method with with_method_fields or
  # with_card; the provider code and the fields of a method come from payments.list_payment_methods.
  # The order details are required: with_buyer, with_billing_address, with_basket_items (at least one
  # item) and with_shipping_address when an item is PHYSICAL (OrderDetails).
  class DirectMethodPaymentRequest
    REQUIRED_FIELDS = %w[paymentMethod amount currency orderId].freeze

    def initialize(amount, currency, order_id)
      @payload = { 'amount' => Money.minor(amount), 'currency' => currency_code(currency), 'orderId' => text(order_id, 'orderId') }
      @payment_method = nil
      @block = nil
      @promissory_note_plan = nil
    end

    # Pays with a method other than card. fields are the provider's inputFields values ({} when the
    # provider asks for nothing). provider_code is required when the method lists more than one
    # provider (providerSelection REQUIRED); BANK_TRANSFER takes none, only the buyer's { bankCode: }.
    def with_method_fields(payment_method, provider_code, fields = {})
      code = MethodFields.normalize_payment_method(payment_method)
      raise ConfigurationError, 'Use with_card(card) to pay by card' if code == PaymentMethod::CARD

      block_name = self.class.method_block_name!(code)
      block = MethodFields.method_fields!(plain(fields, block_name), block_name)
      if code == PaymentMethod::PROMISSORY_NOTE
        raise ConfigurationError, 'Pass the promissory-note schedule with with_promissory_note_schedule, not in the fields' if block.key?('schedule')

        block['noteCount'] = PromissoryNotePlan.note_count!(block['noteCount']) if block.key?('noteCount')
      end
      if code == PaymentMethod::BANK_TRANSFER && !provider_code.nil?
        raise ConfigurationError, "paymentMethod BANK_TRANSFER takes no providerCode: pass nil and the buyer's bank as { bankCode: }"
      end

      @payment_method = code
      @block = provider_code.nil? ? block : { 'providerCode' => MethodFields.provider_code!(provider_code) }.merge(block)
      self
    end

    # Promissory-note plan: one note per row, [{ amount:, dueDate: }], adding up to amount. Replaces a note count.
    def with_promissory_note_schedule(schedule)
      @promissory_note_plan = { 'schedule' => PromissoryNotePlan.schedule!(schedule) }
      self
    end

    # Promissory-note plan: the number of notes (1–24). Replaces a schedule.
    def with_promissory_note_count(count)
      @promissory_note_plan = { 'noteCount' => PromissoryNotePlan.note_count!(count) }
      self
    end

    # Pays by card: new card fields, or cardUserKey + cardToken for a stored card.
    def with_card(card)
      block = plain(card, 'card')
      raise ConfigurationError, 'with_card requires nonempty card fields' if block.empty?

      @payment_method = PaymentMethod::CARD
      @block = block
      self
    end

    # Card only. quote_token binds the charge to a quote from the installment options endpoint.
    def with_installment(count, quote_token = nil)
      raise ConfigurationError, 'installment must be an integer' unless count.is_a?(Integer)

      @payload['installment'] = count
      @payload['installmentQuoteToken'] = text(quote_token, 'installmentQuoteToken') unless quote_token.nil?
      self
    end

    # Card only. true charges with 3D Secure: the response carries a REDIRECT action.
    def with_force3d(value)
      @payload['force3D'] = boolean(value, 'force3D')
      self
    end

    # Pre-authorization: the payment becomes AUTHORIZED; capture or void it later.
    def with_preauth(value)
      @payload['preauth'] = boolean(value, 'preauth')
      self
    end

    # Where the buyer's browser returns after a REDIRECT action.
    def with_callback_url(value)
      assign('callbackUrl', text(value, 'callbackUrl'))
    end

    def with_locale(value)
      assign('locale', text(value, 'locale'))
    end

    def with_description(value)
      assign('description', value)
    end

    def with_customer_id(value)
      assign('customerId', value)
    end

    def with_payment_channel(value)
      assign('paymentChannel', value)
    end

    def with_payment_group(value)
      assign('paymentGroup', value)
    end

    def with_buyer(value)
      assign('buyer', plain(value, 'buyer'))
    end

    def with_billing_address(value)
      assign('billingAddress', plain(value, 'billingAddress'))
    end

    def with_shipping_address(value)
      assign('shippingAddress', plain(value, 'shippingAddress'))
    end

    def with_metadata(value)
      assign('metadata', value)
    end

    def with_basket_items(items)
      raise ConfigurationError, 'basketItems must be an array of objects' unless items.is_a?(Array)

      assign('basketItems', items.map { |item| plain(item, 'basketItems[]') })
    end

    # The gateway body with string keys, checked with the same rules as a raw body.
    def to_h
      raise ConfigurationError, 'Choose the payment method with with_method_fields(method, provider_code, fields) or with_card(card)' unless @payment_method

      block = @block.dup
      if @payment_method == PaymentMethod::PROMISSORY_NOTE && @promissory_note_plan
        raise ConfigurationError, 'The promissory-note plan is given twice: noteCount in the fields and a plan method; use one' if block.key?('noteCount')

        block.merge!(@promissory_note_plan)
      elsif @promissory_note_plan
        raise ConfigurationError, 'A promissory-note plan can only be sent with paymentMethod PROMISSORY_NOTE'
      end
      body = { 'paymentMethod' => @payment_method }.merge(@payload.compact)
      body[MethodFields.block_name_of(@payment_method)] = block
      self.class.payload!(body)
    end

    # Checks a direct/payment body (a Hash or the result of to_h) before sending and returns a
    # string-keyed copy: known fields only, the chosen method's block and no other, card fields only
    # with CARD, block structure, promissory-note plan, shopping-loan basket, no providerCode for
    # BANK_TRANSFER. payments.direct_method_payment also checks the order details (OrderDetails).
    def self.payload!(body)
      raise ConfigurationError, 'A direct method payment needs a body; use DirectMethodPaymentRequest to build it' unless body.is_a?(Hash)

      data = JSON.parse(JsonBody.dump(body))
      raise ConfigurationError, 'Removed amount field; use amount in integer minor units' if %w[price paidPrice].any? { |key| data.key?(key) }

      unknown = data.keys - DIRECT_METHOD_PAYMENT_FIELDS
      raise ConfigurationError, "Unknown direct method payment field(s): #{unknown.join(', ')}" unless unknown.empty?

      missing = REQUIRED_FIELDS.find { |field| data[field].nil? || data[field] == '' }
      raise ConfigurationError, "Direct method payments require '#{missing}'" if missing

      Money.minor(data['amount'])
      method = MethodFields.normalize_payment_method(data['paymentMethod'])
      data['paymentMethod'] = method
      block_name = method == PaymentMethod::CARD ? 'card' : method_block_name!(method)
      blocks!(data, method, block_name)
      PromissoryNotePlan.plan!(data['promissoryNote'], data['amount']) if method == PaymentMethod::PROMISSORY_NOTE
      MethodFields.shopping_loan_basket!(method, data['basketItems'])
      %w[preauth force3D].each do |field|
        raise ConfigurationError, "#{field} must be a JSON boolean" if data.key?(field) && ![true, false].include?(data[field])
      end
      data
    end

    # Block name of a method other than card; a method without a block cannot be paid here yet.
    def self.method_block_name!(code)
      block_name = MethodFields.block_name_of(code)
      return block_name if METHOD_BLOCK_FIELDS.include?(block_name)

      raise ConfigurationError, "paymentMethod #{code} cannot be paid through direct/payment yet; payments.list_payment_methods lists the methods that can"
    end

    def self.blocks!(data, method, block_name)
      if method != PaymentMethod::CARD
        card_field = CARD_ONLY_FIELDS.find { |field| !data[field].nil? }
        raise ConfigurationError, "#{card_field} can only be sent with paymentMethod CARD" if card_field
      end
      other = METHOD_BLOCK_FIELDS.find { |field| field != block_name && !data[field].nil? }
      raise ConfigurationError, "paymentMethod #{method} takes only the '#{block_name}' block; '#{other}' must not be sent" if other

      block = data[block_name]
      raise ConfigurationError, "paymentMethod #{method} requires the '#{block_name}' block" unless block.is_a?(Hash)
      return if method == PaymentMethod::CARD

      method_block!(block, method, block_name)
    end

    def self.method_block!(block, method, block_name)
      if block.key?('providerCode')
        raise ConfigurationError, 'paymentMethod BANK_TRANSFER takes no providerCode in the bankTransfer block' if method == PaymentMethod::BANK_TRANSFER

        MethodFields.provider_code!(block['providerCode'])
      end
      excluded = method == PaymentMethod::PROMISSORY_NOTE ? %w[providerCode schedule] : %w[providerCode]
      MethodFields.method_fields!(block.except(*excluded), block_name)
    end

    private_class_method :blocks!, :method_block!

    private

    def assign(field, value)
      @payload[field] = value
      self
    end

    def plain(value, field)
      raise ConfigurationError, "#{field} must be an object" unless value.is_a?(Hash)

      JSON.parse(JsonBody.dump(value))
    end

    def text(value, field)
      raise ConfigurationError, "#{field} must be a nonempty string" unless value.is_a?(String) && !value.strip.empty?

      value
    end

    def boolean(value, field)
      raise ConfigurationError, "#{field} must be a boolean" unless [true, false].include?(value)

      value
    end

    def currency_code(value)
      code = value.to_s.upcase
      raise ConfigurationError, 'Currency must be a three-letter code' unless code.match?(/\A[A-Z]{3}\z/)

      code
    end
  end
end
