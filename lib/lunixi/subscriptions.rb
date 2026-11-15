# frozen_string_literal: true

module Lunixi
  # Subscriptions (/api/v1/subscriptions, client.subscriptions).
  #
  # Calls carry the access token minted from your API key (no per-request signature). Creating a
  # subscription needs an Idempotency-Key (reuse it when retrying the same subscription; it is sent in the
  # body too); plan, customer, card, plan-change and charge-retry writes accept one.
  #
  # Bodies and filters are checked against SUBSCRIPTION_ROUTES before anything is sent: an unknown field
  # or filter, a missing required field, a value outside its set or a non-canonical amount raises
  # ConfigurationError. Keys are the wire names (String or Symbol; snake_case works too). Amounts are
  # canonical minor-unit strings ("9900" = 99.00 TRY; "0" for a free plan), checked in bodies, filters and
  # answers.
  #
  # Entity calls return the envelope's data; lists return a Lunixi::ListPage. For the subscription, plan,
  # customer, card, invoice and audit-log lists send next_cursor back as page_token: (page_size is the
  # envelope's pageSize). The related resources hang off plans, customers, cards, invoices, portal,
  # products, features, addons and usage.
  class Subscriptions
    attr_reader :plans, :customers, :cards, :invoices, :portal, :products, :features, :addons, :usage

    # True while the subscription may be billed (TRIALING, ACTIVE, PAST_DUE). Takes a subscription Hash or
    # its status.
    def self.active?(subscription)
      SubscriptionStatus::ACTIVE_STATES.include?(status_of(subscription))
    end

    # True for UPGRADED, DOWNGRADED, CANCELED and EXPIRED.
    def self.terminal?(subscription)
      SubscriptionStatus::TERMINAL_STATES.include?(status_of(subscription))
    end

    # Hosted portal URL of a portal link (the portal.create_portal_link answer, or its token).
    def self.portal_url(link, base = SUBSCRIPTION_PORTAL_HOSTED_BASE)
      token = link.is_a?(Hash) ? link['token'] : link
      token = '' unless token.is_a?(String)
      "#{base.to_s.sub(%r{/+\z}, '')}/?token=#{URI.encode_www_form_component(token).gsub('+', '%20')}"
    end

    def self.status_of(subscription)
      return subscription if subscription.is_a?(String)

      subscription.is_a?(Hash) && subscription['status'].is_a?(String) ? subscription['status'] : ''
    end
    private_class_method :status_of

    def initialize(client)
      @routes = RouteTable.new(client, SUBSCRIPTION_ROUTES)
      @plans = SubscriptionPlans.new(@routes)
      @customers = SubscriptionCustomers.new(@routes)
      @cards = SubscriptionCards.new(@routes)
      @invoices = SubscriptionInvoices.new(@routes)
      @portal = SubscriptionPortal.new(@routes)
      @products = SubscriptionProducts.new(@routes)
      @features = SubscriptionFeatures.new(@routes)
      @addons = SubscriptionAddons.new(@routes)
      @usage = SubscriptionUsage.new(@routes)
    end

    # { customerId, planId, paymentCardId?, paymentMethodId?, collectionMethod?, priceUpdatePolicy?,
    # entitlementPolicy?, billingTimezone?, startsAt?, chargeOnCreate?, billingCycleAnchorOverride?,
    # skipTrial?, metadata? }. The Idempotency-Key is required (idempotency_key: or the request's
    # idempotencyKey; both given, they must agree) and is sent in the body as well.
    def create(request, idempotency_key: nil)
      body = RouteRequest.wire_hash!(request, 'create request')
      key = RouteTable.idempotency_key_of('create', body, idempotency_key)
      body['idempotencyKey'] = key.strip if key.is_a?(String) && !key.strip.empty?
      RouteValue.one_of!(body['collectionMethod'], SubscriptionCollectionMethod::ALL, 'collectionMethod') if body.key?('collectionMethod')
      SubscriptionRules.boolean!(body, 'chargeOnCreate')
      SubscriptionRules.boolean!(body, 'skipTrial')
      raise ConfigurationError, "'metadata' must be a Hash." if body.key?('metadata') && !body['metadata'].is_a?(Hash)

      @routes.data('create', body: body, idempotency_key: key)
    end

    def get(subscription_id)
      @routes.data('get', params: { 'subscriptionId' => subscription_id })
    end

    # Filters: customerId, status, pageSize, pageToken.
    def list(**filters)
      @routes.token_page('list', query: filters)
    end

    def iterate(**filters, &block)
      RouteResponse.each_item(filters, block, :pageToken) { |query| list(**query) }
    end

    # Cancels now, or at the period end with at_period_end: true.
    def cancel(subscription_id, at_period_end: false, reason: nil)
      raise ConfigurationError, "'at_period_end' must be true or false." unless [true, false].include?(at_period_end)

      body = RouteRequest.compact('cancelAtPeriodEnd' => at_period_end, 'reason' => RouteValue.optional_text(reason, 'reason'))
      @routes.data('cancel', params: { 'subscriptionId' => subscription_id }, body: body)
    end

    # Pauses billing; resume_at (ISO 8601) resumes it automatically.
    def pause(subscription_id, resume_at: nil)
      body = RouteRequest.compact('resumeAt' => RouteValue.optional_text(resume_at, 'resumeAt'))
      @routes.data('pause', params: { 'subscriptionId' => subscription_id }, body: body)
    end

    def resume(subscription_id)
      @routes.data('resume', params: { 'subscriptionId' => subscription_id })
    end

    # { newPlanId, behavior?: IMMEDIATE | NEXT_PERIOD, reason? }. An Idempotency-Key (idempotency_key: or
    # the request's idempotencyKey) is sent in the header and the body.
    def change_plan(subscription_id, request, idempotency_key: nil)
      body = RouteRequest.wire_hash!(request, 'changePlan request')
      key = RouteTable.idempotency_key_of('changePlan', body, idempotency_key)
      body['idempotencyKey'] = key.strip if key.is_a?(String) && !key.strip.empty?
      body['behavior'] = RouteValue.one_of!(body['behavior'].to_s.upcase, SubscriptionPlanChangeBehavior::ALL, 'behavior') if body.key?('behavior')
      @routes.data('changePlan', params: { 'subscriptionId' => subscription_id }, body: body, idempotency_key: key)
    end

    # The audit trail of a subscription; filters limit, pageToken.
    def audit_logs(subscription_id, **filters)
      @routes.token_page('auditLogs', params: { 'subscriptionId' => subscription_id }, query: filters)
    end

    def inspect
      '#<Lunixi::Subscriptions>'
    end
  end

  # Field rules of the subscription bodies (plans, cards, the subscription itself). Not a public API.
  module SubscriptionRules
    module_function

    def boolean!(body, field, label = field)
      return unless body.key?(field)
      raise ConfigurationError, "'#{label}' must be true or false." unless [true, false].include?(body[field])
    end

    def count!(body, field, min, label = field)
      return unless body.key?(field)
      raise ConfigurationError, "'#{label}' must be an integer of at least #{min}." unless body[field].is_a?(Integer) && body[field] >= min
    end

    def integers!(values, field, min, max = nil)
      valid = values.is_a?(Array) && values.all? { |value| value.is_a?(Integer) && value >= min && (max.nil? || value <= max) }
      raise ConfigurationError, "'#{field}' must be an array of integers from #{min}#{" to #{max}" if max}." unless valid

      values.dup
    end

    # A gateway currency (ISO 4217, upper case).
    def currency!(value, field = 'currency')
      currency = value.is_a?(String) ? value.strip.upcase : ''
      return currency if Money::EXPONENTS.key?(currency)

      raise ConfigurationError, "'#{field}' must be a supported currency (#{Money::EXPONENTS.keys.join(', ')})."
    end

    # The plan body: trimmed ids, the price present (its form is checked with the other money members),
    # a supported currency, the billing rule and the dunning counts.
    def plan!(request)
      body = RouteRequest.wire_hash!(request, 'plans.create request')
      %w[productId code name].each { |field| body[field] = RouteValue.text!(body[field], field) if body.key?(field) }
      raise ConfigurationError, 'plans.create requires price.' unless body.key?('price')

      body['currency'] = currency!(body['currency']) if body.key?('currency')
      body['billing'] = billing_rule!(body['billing']) if body.key?('billing')
      %w[trialPeriodDays maxDunningAttempts gracePeriodDays].each { |field| count!(body, field, 0) }
      body['dunningScheduleDays'] = integers!(body['dunningScheduleDays'], 'dunningScheduleDays', 0) if body.key?('dunningScheduleDays')
      body
    end

    # { frequency, interval? (default 1), byMonthDay?, byWeekDay?, timezone?, lastDayOfMonthFix?, count? }.
    def billing_rule!(value)
      rule = RouteRequest.wire_keys!(value, SUBSCRIPTION_BILLING_RULE_FIELDS, 'billing')
      rule['frequency'] = RouteValue.one_of!(rule['frequency'].to_s.upcase, SubscriptionBillingFrequency::ALL, 'billing.frequency')
      rule['interval'] = 1 unless rule.key?('interval')
      count!(rule, 'interval', 1, 'billing.interval')
      count!(rule, 'count', 0, 'billing.count')
      rule['byMonthDay'] = integers!(rule['byMonthDay'], 'billing.byMonthDay', 1, 31) if rule.key?('byMonthDay')
      if rule.key?('byWeekDay') && !(rule['byWeekDay'].is_a?(Array) && rule['byWeekDay'].all?(String))
        raise ConfigurationError, "'billing.byWeekDay' must be an array of week days (MO, TU, WE, TH, FR, SA, SU)."
      end

      boolean!(rule, 'lastDayOfMonthFix', 'billing.lastDayOfMonthFix')
      rule
    end

    # The saved-card body: a paymentMethodToken, never a card number (an unknown field is refused by name).
    def card!(request)
      body = RouteRequest.wire_hash!(request, 'cards.add request')
      RouteValue.one_of!(body['verificationMode'], SubscriptionCardVerificationMode::ALL, 'verificationMode') if body.key?('verificationMode')
      count!(body, 'expireMonth', 1)
      count!(body, 'expireYear', 1)
      boolean!(body, 'isDefault')
      if body.key?('supportedCurrencies')
        raise ConfigurationError, "'supportedCurrencies' must be an array." unless body['supportedCurrencies'].is_a?(Array)

        body['supportedCurrencies'] = body['supportedCurrencies'].map { |currency| currency!(currency, 'supportedCurrencies') }
      end
      body
    end
  end
end
