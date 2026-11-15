# frozen_string_literal: true

module Lunixi
  # Method blocks a non-card split leg can carry. Meal card, open banking, shopping loan and bank
  # transfer cannot be split payment legs.
  SPLIT_LEG_BLOCK_FIELDS = %w[mobileBilling wallet promissoryNote].freeze

  # Fields of one split leg.
  SPLIT_PAYMENT_LEG_FIELDS = (%w[paymentMethod cardToken amount force3D installment installmentQuoteToken] + SPLIT_LEG_BLOCK_FIELDS).freeze

  # Filters of payments.list_splits (GET /payments/split).
  LIST_SPLIT_PAYMENTS_FILTERS = %w[status currency createdFrom createdTo orderId ownerRef limit after].freeze

  # Put this key into a webhook endpoint's event types to also receive the events of each leg. It is
  # not an event type and payment.* does not include it.
  SPLIT_LEG_EVENTS_SUBSCRIPTION = 'payment.split.leg_events'

  # Status of a split payment (status).
  module SplitPaymentStatus
    COMPOSING = 'COMPOSING'
    AUTHORIZING = 'AUTHORIZING'
    AWAITING_3DS = 'AWAITING_3DS'
    AWAITING_ACTION = 'AWAITING_ACTION'
    AWAITING_CREDIT_APPROVAL = 'AWAITING_CREDIT_APPROVAL'
    AWAITING_REPLACEMENT_CARD = 'AWAITING_REPLACEMENT_CARD'
    AUTHORIZED = 'AUTHORIZED'
    CAPTURING = 'CAPTURING'
    COMPLETED = 'COMPLETED'
    COMPENSATING = 'COMPENSATING'
    VOIDED = 'VOIDED'
    FAILED = 'FAILED'
    RECONCILIATION_REQUIRED = 'RECONCILIATION_REQUIRED'

    ALL = [COMPOSING, AUTHORIZING, AWAITING_3DS, AWAITING_ACTION, AWAITING_CREDIT_APPROVAL, AWAITING_REPLACEMENT_CARD,
           AUTHORIZED, CAPTURING, COMPLETED, COMPENSATING, VOIDED, FAILED, RECONCILIATION_REQUIRED].freeze
  end

  # Webhook events of a split payment. The result of the main payment arrives as payment.captured /
  # payment.failed with settlementMode SPLIT; deliver the order on that event.
  module SplitPaymentEvents
    COMPLETED = 'payment.split.completed'
    VOIDED = 'payment.split.voided'
    COMPENSATING = 'payment.split.compensating'
    # The non-reversible leg's result is being confirmed; card holds are kept until then.
    OUTCOME_PENDING = 'payment.split.outcome_pending'
    # The order could not be fully collected.
    RECONCILIATION_REQUIRED = 'payment.split.reconciliation_required'
    # Leg event: a charged leg is being refunded and retried until it succeeds.
    LEG_REFUND_PENDING = 'payment.split.leg_refund_pending'

    ALL = [COMPLETED, VOIDED, COMPENSATING, OUTCOME_PENDING, RECONCILIATION_REQUIRED, LEG_REFUND_PENDING].freeze
  end

  # Leg and list rules of the split payment endpoints.
  module SplitPaymentRules
    LIST_MAX_LIMIT = 100
    LIST_MAX_VALUES = 20
    FILTER_TEXT_MAX_LENGTH = 200
    AFTER_MAX_LENGTH = 2048
    ISO_8601 = /\A\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}(:\d{2}(\.\d{1,9})?)?(Z|[+-]\d{2}:?\d{2})?)?\z/

    module_function

    # A card leg (paymentMethod omitted, empty or CARD) carries no method block; a non-card leg carries
    # only its own block, which must be one of SPLIT_LEG_BLOCK_FIELDS.
    def leg!(leg, path)
      excluded = (METHOD_BLOCK_FIELDS - SPLIT_LEG_BLOCK_FIELDS).find { |field| !leg[field].nil? }
      raise ConfigurationError, "#{path}: the '#{excluded}' block cannot be sent in a split payment leg" if excluded

      method = leg['paymentMethod']
      if [nil, '', PaymentMethod::CARD].include?(method)
        block = SPLIT_LEG_BLOCK_FIELDS.find { |field| !leg[field].nil? }
        raise ConfigurationError, "#{path} is a card leg and cannot carry the '#{block}' block" if block

        return
      end
      method_leg!(leg, path, MethodFields.normalize_payment_method(method))
    end

    # Query of GET /payments/split; status and currency may be a value or a list (repeated parameters).
    def list_query!(filters)
      data = filters.transform_keys(&:to_s)
      unknown = data.keys - LIST_SPLIT_PAYMENTS_FILTERS
      raise ConfigurationError, "list_splits does not take #{unknown.join(', ')}; filters: #{LIST_SPLIT_PAYMENTS_FILTERS.join(', ')}" unless unknown.empty?

      LIST_SPLIT_PAYMENTS_FILTERS.each_with_object({}) do |key, query|
        value = data[key]
        next if value.nil? || value == ''

        query[key] = filter_value!(key, value)
      end
    end

    def method_leg!(leg, path, method)
      block_name = MethodFields.block_name_of(method)
      unless SPLIT_LEG_BLOCK_FIELDS.include?(block_name)
        raise ConfigurationError, "#{path}: paymentMethod #{method} cannot be a split leg; a non-card leg carries one of #{SPLIT_LEG_BLOCK_FIELDS.join(', ')}"
      end

      other = SPLIT_LEG_BLOCK_FIELDS.find { |field| field != block_name && !leg[field].nil? }
      raise ConfigurationError, "#{path}: paymentMethod #{method} takes only the '#{block_name}' block" if other

      block = leg[block_name]
      raise ConfigurationError, "#{path}: paymentMethod #{method} requires the '#{block_name}' block" unless block.is_a?(Hash)

      fields = block.except('providerCode')
      MethodFields.provider_code!(block['providerCode']) unless block['providerCode'].nil?
      MethodFields.method_fields!(fields, "#{path}.#{block_name}")
      return unless method == PaymentMethod::PROMISSORY_NOTE
      raise ConfigurationError, "#{path}.#{block_name}.schedule cannot be sent in a split leg; use noteCount" unless fields['schedule'].nil?

      PromissoryNotePlan.note_count!(fields['noteCount'], "#{path}.#{block_name}.noteCount")
    end

    def filter_value!(key, value)
      case key
      when 'status' then values!(key, value) { |entry| SplitPaymentStatus::ALL.include?(entry) }
      when 'currency' then values!(key, value) { |entry| entry.is_a?(String) && entry.match?(/\A[A-Z]{3}\z/) }
      when 'createdFrom', 'createdTo'
        raise ConfigurationError, "#{key} must be an ISO 8601 date-time" unless value.is_a?(String) && value.match?(ISO_8601)

        value
      when 'limit'
        raise ConfigurationError, "limit must be an integer from 1 to #{LIST_MAX_LIMIT}" unless value.is_a?(Integer) && value.between?(1, LIST_MAX_LIMIT)

        value.to_s
      else
        max = key == 'after' ? AFTER_MAX_LENGTH : FILTER_TEXT_MAX_LENGTH
        return value if value.is_a?(String) && !value.strip.empty? && value.length <= max

        raise ConfigurationError, "#{key} must be a nonempty string of at most #{max} characters"
      end
    end

    def values!(key, value, &)
      values = Array(value)
      raise ConfigurationError, "#{key} takes 1 to #{LIST_MAX_VALUES} values" if values.empty? || values.size > LIST_MAX_VALUES
      raise ConfigurationError, "#{key} contains an invalid value" unless values.all?(&)

      values
    end

    private_class_method :method_leg!, :filter_value!, :values!
  end
end
