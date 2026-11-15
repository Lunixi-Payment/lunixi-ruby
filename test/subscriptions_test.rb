# frozen_string_literal: true

require_relative 'test_helper'

# Subscription calls go through SUBSCRIPTION_ROUTES with the access token only; bodies, filters and the
# money members of answers are checked before and after sending. Ids and names are synthetic.
class SubscriptionsTest < Minitest::Test
  def setup
    @answer = { 'success' => true, 'data' => { 'id' => 'sub_1', 'status' => 'ACTIVE' } }
    @transport = RecordingTransport.new { response(200, @answer) }
    @subscriptions = client(transport: @transport).subscriptions
  end

  def test_sub_clients_and_bearer_only_routes
    %i[plans customers cards invoices portal products features addons usage].each do |name|
      assert @subscriptions.public_send(name), name
    end
    Lunixi::SUBSCRIPTION_ROUTES.each do |name, route|
      refute route['stepUp'], name
      assert_match %r{\A/api/(?:v1|panel/v1)/subscriptions/}, route['path'], name
    end
    assert_equal 'required', Lunixi::SUBSCRIPTION_ROUTES.fetch('create')['idempotencyKey']
  end

  def test_create_sends_the_key_in_the_header_and_the_body
    subscription = @subscriptions.create({ customer_id: 'cus_1', planId: 'plan_1', collectionMethod: 'AUTO_CHARGE' },
                                         idempotency_key: 'idem-sub-1')
    assert_equal 'sub_1', subscription['id']
    call = api_calls(@transport).fetch(0)
    assert_equal ['POST', '/api/v1/subscriptions/subscriptions'], [call[:method], call[:uri].path]
    assert_equal 'Bearer at_TEST_synthetic', call[:headers]['Authorization']
    refute call[:headers].key?('X-Signature')
    assert_equal 'idem-sub-1', call[:headers]['Idempotency-Key']
    assert_equal({ 'customerId' => 'cus_1', 'planId' => 'plan_1', 'collectionMethod' => 'AUTO_CHARGE', 'idempotencyKey' => 'idem-sub-1' },
                 sent_json(call))
  end

  def test_create_takes_the_key_from_the_request
    @subscriptions.create({ customerId: "cus_1", planId: "plan_1", idempotencyKey: "idem-sub-2" })
    assert_equal 'idem-sub-2', api_calls(@transport).fetch(0)[:headers]['Idempotency-Key']
  end

  def test_local_errors_send_nothing
    [
      -> { @subscriptions.create({ customerId: 'cus_1', planId: 'plan_1' }) },
      -> { @subscriptions.create({ customerId: 'cus_1', planId: 'plan_1', idempotencyKey: 'a' }, idempotency_key: 'b') },
      -> { @subscriptions.create({ customerId: 'cus_1', planId: 'plan_1', coupon: 'X' }, idempotency_key: 'idem-1') },
      -> { @subscriptions.create({ customerId: 'cus_1', planId: 'plan_1', collectionMethod: 'CASH' }, idempotency_key: 'idem-1') },
      -> { @subscriptions.cancel('sub_1', at_period_end: 'yes') },
      -> { @subscriptions.change_plan('sub_1', { newPlanId: 'plan_2', behavior: 'LATER' }) },
      -> { @subscriptions.get(' ') },
      -> { @subscriptions.list(state: 'ACTIVE') },
      -> { @subscriptions.invoices.retry_charge('inv_1', idempotency_key: "bad\nkey") },
      -> { @subscriptions.plans.update('plan_1', nil) },
      -> { @subscriptions.customers.adjust_credit('cus_1', { amountMinor: 5, currency: 'TRY' }) }
    ].each { |call| assert_raises(Lunixi::ConfigurationError) { call.call } }
    assert_empty api_calls(@transport)
  end

  def test_cancel_pause_resume_and_change_plan
    @subscriptions.cancel('sub_1', at_period_end: true, reason: 'customer request')
    @subscriptions.pause('sub_1')
    @subscriptions.resume('sub_1')
    @subscriptions.change_plan('sub_1', { new_plan_id: 'plan_2', behavior: 'next_period' }, idempotency_key: 'idem-change-1')
    cancel, pause, resume, change = api_calls(@transport)
    assert_equal '/api/v1/subscriptions/subscriptions/sub_1/cancel', cancel[:uri].path
    assert_equal({ 'cancelAtPeriodEnd' => true, 'reason' => 'customer request' }, sent_json(cancel))
    assert_nil pause[:body]
    assert_nil resume[:body]
    assert_equal '/api/v1/subscriptions/subscriptions/sub_1/change-plan', change[:uri].path
    assert_equal({ 'newPlanId' => 'plan_2', 'behavior' => 'NEXT_PERIOD', 'idempotencyKey' => 'idem-change-1' }, sent_json(change))
    assert_equal 'idem-change-1', change[:headers]['Idempotency-Key']
  end

  def test_cursor_lists_read_next_page_token_and_page_size
    @answer = { 'success' => true, 'data' => [{ 'id' => 'plan_1', 'price' => '9900', 'currency' => 'TRY' }], 'nextPageToken' => 'tok_next',
                'pageSize' => 20 }
    page = @subscriptions.plans.list(includeArchived: false, product_id: 'prod_1')
    assert_equal '9900', page.items.first['price']
    assert_equal 'tok_next', page.next_cursor
    assert page.has_more?
    assert_equal 20, page.page_size
    assert_equal({ 'includeArchived' => 'false', 'productId' => 'prod_1' }, URI.decode_www_form(api_calls(@transport).fetch(0)[:uri].query).to_h)
  end

  def test_iterate_sends_the_token_back_as_page_token
    pages = [{ 'data' => [{ 'id' => 'sub_1' }], 'nextPageToken' => 'tok_2' }, { 'data' => [{ 'id' => 'sub_2' }] }]
    transport = RecordingTransport.new { response(200, pages.shift) }
    ids = client(transport: transport).subscriptions.iterate(status: 'ACTIVE').map { |row| row['id'] }
    assert_equal %w[sub_1 sub_2], ids
    assert_equal({ 'status' => 'ACTIVE', 'pageToken' => 'tok_2' }, URI.decode_www_form(api_calls(transport).fetch(1)[:uri].query).to_h)
  end

  def test_plans_create_checks_price_currency_and_billing
    plan = { productId: 'prod_1', code: 'free', name: 'Free', price: '0', currency: 'try', billing: { frequency: 'monthly' } }
    @subscriptions.plans.create(plan, idempotency_key: 'idem-plan-1')
    call = api_calls(@transport).fetch(0)
    assert_equal '/api/v1/subscriptions/plans', call[:uri].path
    assert_equal 'idem-plan-1', call[:headers]['Idempotency-Key']
    assert_equal({ 'frequency' => 'MONTHLY', 'interval' => 1 }, sent_json(call)['billing'])
    assert_equal 'TRY', sent_json(call)['currency']
    [
      plan.merge(price: 9900), plan.merge(price: '99.00'), plan.reject { |key, _| key == :price }, plan.merge(currency: 'XXX'),
      plan.merge(billing: { frequency: 'HOURLY' }), plan.merge(billing: { frequency: 'DAILY', interval: 0 }),
      plan.merge(billing: { frequency: 'DAILY', anchor: 1 }), plan.merge(trialPeriodDays: -1), plan.merge(dunningScheduleDays: [1, 'x'])
    ].each { |body| assert_raises(Lunixi::ConfigurationError) { @subscriptions.plans.create(body) } }
    assert_equal 1, api_calls(@transport).size
  end

  def test_an_answer_with_a_numeric_amount_is_refused
    @answer = { 'success' => true, 'data' => { 'id' => 'inv_1', 'totalAmount' => 9900 } }
    error = assert_raises(Lunixi::ConfigurationError) { @subscriptions.invoices.get('inv_1') }
    assert_match(/totalAmount/, error.message)
  end

  def test_cards_add_refuses_a_card_number_without_echoing_it
    @subscriptions.cards.add({ customerId: 'cus_1', paymentMethodToken: 'tok_abc', last4: '4242', expireMonth: 12, expireYear: 2030,
                               isDefault: true, supportedCurrencies: %w[try] })
    body = sent_json(api_calls(@transport).fetch(0))
    assert_equal 'tok_abc', body['paymentMethodToken']
    assert_equal %w[TRY], body['supportedCurrencies']
    error = assert_raises(Lunixi::ConfigurationError) do
      @subscriptions.cards.add({ customerId: 'cus_1', paymentMethodToken: 'tok_abc', cardNumber: '4111111111111111' })
    end
    assert_match(/cardNumber/, error.message)
    refute_match(/4111/, error.message)
    assert_equal 1, api_calls(@transport).size
  end

  def test_cards_and_invoices
    @answer = { 'success' => true, 'data' => [] }
    @subscriptions.cards.list('cus_1', page_size: 10)
    @subscriptions.cards.set_default('card_1')
    @subscriptions.cards.deactivate('card_1')
    @subscriptions.invoices.list(subscriptionId: 'sub_1', status: 'OPEN')
    @subscriptions.invoices.void('inv_1', reason: 'duplicate')
    @subscriptions.invoices.retry_charge('inv_1', idempotency_key: 'idem-retry-1')
    list, default, deactivate, invoices, void, retry_charge = api_calls(@transport)
    assert_equal 'customerId=cus_1&includeInactive=false&pageSize=10', list[:uri].query
    assert_equal '/api/v1/subscriptions/cards/card_1/set-default', default[:uri].path
    assert_equal 'DELETE', deactivate[:method]
    assert_nil deactivate[:body]
    assert_equal 'subscriptionId=sub_1&status=OPEN', invoices[:uri].query
    assert_equal({ 'reason' => 'duplicate' }, sent_json(void))
    assert_equal '/api/v1/subscriptions/invoices/inv_1/retry-charge', retry_charge[:uri].path
    assert_equal 'idem-retry-1', retry_charge[:headers]['Idempotency-Key']
  end

  def test_customers
    @subscriptions.customers.upsert({ externalId: 'u-42', email: 'customer@example.com' }, idempotency_key: 'idem-cus-1')
    @subscriptions.customers.get_by_external_id('u-42')
    @subscriptions.customers.adjust_credit('cus_1', { amountMinor: '500', currency: 'TRY', type: 'GRANT' })
    upsert, lookup, adjust = api_calls(@transport)
    assert_equal ['PUT', '/api/v1/subscriptions/customers'], [upsert[:method], upsert[:uri].path]
    assert_equal '/api/v1/subscriptions/customers/by-external/u-42', lookup[:uri].path
    assert_equal '/api/v1/subscriptions/customers/cus_1/credit-balance/adjust', adjust[:uri].path
  end

  def test_portal_sdk_session_reads_the_proof_at_the_envelope_root
    @answer = { 'success' => true, 'portalToken' => 'cp_abc', 'sessionProof' => 'proof_xyz', 'nonce' => 'nonce_1',
                'expiresAt' => '2026-06-16T03:00:00Z' }
    session = @subscriptions.portal.create_sdk_session('cus_1', 'https://shop.example', sdk_mode: Lunixi::SubscriptionPortalSdkMode::HYBRID)
    assert_equal %w[cp_abc proof_xyz nonce_1 2026-06-16T03:00:00Z], session.values_at('portalToken', 'sessionProof', 'proofNonce', 'proofExpiresAt')
    call = api_calls(@transport).fetch(0)
    assert_equal '/api/v1/subscriptions/portal/sdk-session', call[:uri].path
    assert_equal({ 'customerId' => 'cus_1', 'origin' => 'https://shop.example', 'sdkMode' => 'HYBRID' }, sent_json(call))
    assert_raises(Lunixi::ConfigurationError) { @subscriptions.portal.create_sdk_session('cus_1', 'https://shop.example', sdk_mode: 'EMBED') }
  end

  def test_portal_links_use_the_panel_route
    @answer = { 'success' => true, 'data' => { 'id' => 'lnk_1', 'token' => 'cp_xyz', 'status' => 'ACTIVE' } }
    link = @subscriptions.portal.create_portal_link('cus_1', allowedPlanIds: ['plan_1'])
    assert_equal 'https://portal.lunixi.com/?token=cp_xyz', Lunixi::Subscriptions.portal_url(link)
    @subscriptions.portal.revoke_link('lnk_1')
    create, revoke = api_calls(@transport)
    assert_equal '/api/panel/v1/subscriptions/portal/links', create[:uri].path
    assert_equal({ 'allowedPlanIds' => ['plan_1'], 'customerId' => 'cus_1' }, sent_json(create))
    assert_equal ['DELETE', '/api/panel/v1/subscriptions/portal/links/lnk_1'], [revoke[:method], revoke[:uri].path]
    assert_nil revoke[:body]
  end

  def test_catalog_feature_addon_and_usage_routes
    @answer = { 'success' => true, 'data' => { 'items' => [], 'pageInfo' => { 'hasMore' => false, 'nextCursor' => nil } } }
    page = @subscriptions.products.list(limit: 5, active: true)
    refute page.has_more?
    @subscriptions.products.upsert_translation('prod_1', 'en', { name: 'Pro' })
    @subscriptions.features.list(key: 'api_calls')
    @subscriptions.features.delete('feat_1')
    @subscriptions.addons.deactivate('addon_1')
    @subscriptions.usage.record({ subscriptionId: 'sub_1', featureKey: 'api_calls', quantity: 3 })
    @subscriptions.usage.check_entitlement({ subscriptionId: 'sub_1', featureKey: 'api_calls' })
    products, translation, features, feature, addon, record, check = api_calls(@transport)
    assert_equal 'limit=5&active=true', products[:uri].query
    assert_equal ['PATCH', '/api/v1/subscriptions/products/prod_1/translations/en'], [translation[:method], translation[:uri].path]
    assert_equal 'key=api_calls', features[:uri].query
    assert_equal 'DELETE', feature[:method]
    assert_equal '/api/v1/subscriptions/addons/addon_1', addon[:uri].path
    assert_equal '/api/v1/subscriptions/usage/record', record[:uri].path
    assert_equal '/api/v1/subscriptions/usage/check-entitlement', check[:uri].path
  end

  def test_status_helpers
    assert Lunixi::Subscriptions.active?('PAST_DUE')
    assert Lunixi::Subscriptions.active?({ 'status' => 'TRIALING' })
    refute Lunixi::Subscriptions.active?('PAUSED')
    assert Lunixi::Subscriptions.terminal?('CANCELED')
    refute Lunixi::Subscriptions.terminal?(nil)
  end
end
