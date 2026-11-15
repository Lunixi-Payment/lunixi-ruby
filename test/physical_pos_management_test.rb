# frozen_string_literal: true

require_relative 'test_helper'

# Physical POS management: paths, bodies, the rowVersion and Idempotency-Key rules, 201 / 200, pages
# and local refusals. Ids and values are synthetic.
class PhysicalPosManagementTest < Minitest::Test
  BASE = '/api/v1/physical-pos'
  KEY = 'pos-manage-key-0001'
  STORE_ID = 'st_1'
  DEVICE_ID = 'dv_1'
  TERMINAL_ID = 'tm_1'

  def setup
    @answers = []
    @transport = RecordingTransport.new { |_request| @answers.empty? ? response(200, { 'data' => {} }) : @answers.shift }
    @manage = client(transport: @transport).physical_pos_management
  end

  def gateway_calls
    @transport.calls.reject { |call| call[:uri].path == '/api/v1/auth/token' }
  end

  def last_call
    gateway_calls.last
  end

  def sent_body
    JSON.parse(last_call[:body])
  end

  def assert_nothing_sent
    before = gateway_calls.size
    yield
    assert_equal before, gateway_calls.size, 'nothing may be sent'
  end

  def assert_route(method, path)
    assert_equal [method, BASE + path], [last_call[:method], last_call[:uri].path]
    assert last_call[:headers].key?('X-Signature'), "#{method} #{path} must be signed"
  end

  def test_create_store_is_keyed_and_returns_created_or_ok
    @answers << response(201, { 'data' => { 'store' => { 'storeId' => STORE_ID, 'rowVersion' => 1 } } })
    result = @manage.create_store({ code: 'IST-01', name: 'Kadikoy', city: '', timezone: 'Europe/Istanbul' })
    assert_route 'POST', '/stores'
    assert_equal({ 'code' => 'IST-01', 'name' => 'Kadikoy', 'timezone' => 'Europe/Istanbul' }, sent_body)
    key = last_call[:headers]['Idempotency-Key']
    assert_match(/\A\h{8}-\h{4}-4\h{3}-[89ab]\h{3}-\h{12}\z/, key)
    assert_equal [201, key, STORE_ID], [result.status_code, result.idempotency_key, result['store']['storeId']]

    @answers << response(200, { 'data' => { 'store' => { 'storeId' => STORE_ID }, 'replayed' => true } })
    replay = @manage.create_store({ code: 'IST-01', name: 'Kadikoy' }, idempotency_key: KEY)
    assert_equal [200, true, KEY], [replay.status_code, replay.replayed, last_call[:headers]['Idempotency-Key']]
  end

  def test_updates_send_row_version_and_explicit_clears
    @answers << response(200, { 'data' => { 'store' => { 'storeId' => STORE_ID, 'rowVersion' => 4 } } })
    store = @manage.update_store(STORE_ID, { rowVersion: 3, city: nil, name: 'Moda', timezone: nil })
    assert_route 'PATCH', "/stores/#{STORE_ID}"
    assert_equal({ 'rowVersion' => 3, 'name' => 'Moda', 'city' => nil }, sent_body)
    refute last_call[:headers].key?('Idempotency-Key')
    assert_equal 4, store['rowVersion']

    assert_nothing_sent do
      [{ name: 'x' }, { rowVersion: 0 }, { rowVersion: '3' }, { rowVersion: 2_147_483_648 }, { rowVersion: 3, code: 'x' }].each do |request|
        assert_raises(Lunixi::ConfigurationError, request.inspect) { @manage.update_store(STORE_ID, request) }
      end
    end
  end

  def test_status_changes
    @manage.archive_store(STORE_ID, { rowVersion: 2, reasonCode: 'CLOSED' })
    assert_route 'POST', "/stores/#{STORE_ID}/archive"
    assert_equal({ 'rowVersion' => 2, 'reasonCode' => 'CLOSED' }, sent_body)
    @manage.restore_register('rg_1', { rowVersion: 5, reasonCode: 'REOPENED' })
    assert_route 'POST', '/registers/rg_1/restore'
    @manage.close_terminal(TERMINAL_ID, { rowVersion: 1, reasonCode: 'REPLACED' })
    assert_route 'POST', "/terminals/#{TERMINAL_ID}/close"
    assert_nothing_sent do
      assert_raises(Lunixi::ConfigurationError) { @manage.archive_register('rg_1', { rowVersion: 1 }) }
      assert_raises(Lunixi::ConfigurationError) { @manage.archive_register('rg_1', { rowVersion: 1, reasonCode: '' }) }
    end
  end

  def test_registers_and_terminals
    @manage.create_register(STORE_ID, { code: 'K1', name: 'Till 1' }, idempotency_key: KEY)
    assert_route 'POST', "/stores/#{STORE_ID}/registers"
    assert_equal KEY, last_call[:headers]['Idempotency-Key']
    @manage.create_terminal({ code: 'T1', displayName: 'Front', vendorCode: 'VENDOR' })
    assert_route 'POST', '/terminals'
    @manage.add_terminal_acquirer(TERMINAL_ID, { vendorAcquirerRef: 'acq', merchantNumber: 'm1', terminalNumber: 't1', currencies: %w[TRY USD] })
    assert_route 'POST', "/terminals/#{TERMINAL_ID}/acquirers"
    assert_equal %w[TRY USD], sent_body['currencies']
    @manage.update_terminal_acquirer('ta_1', { rowVersion: 2, label: nil, status: 'DISABLED' })
    assert_route 'PATCH', '/terminal-acquirers/ta_1'
    assert_equal({ 'rowVersion' => 2, 'label' => nil, 'status' => 'DISABLED' }, sent_body)
    @manage.add_terminal_provider(TERMINAL_ID, { vendorAccountId: 'va_1', merchantCode: 'M', terminalCode: 'T', productCode: 'MEAL' })
    assert_route 'POST', "/terminals/#{TERMINAL_ID}/providers"
    @manage.update_terminal_provider('tp_1', { rowVersion: 1, label: nil })
    assert_route 'PATCH', '/terminal-providers/tp_1'
    @manage.change_terminal_device(TERMINAL_ID, { rowVersion: 1, deviceId: DEVICE_ID, reasonCode: 'REPLACED' })
    assert_route 'POST', "/terminals/#{TERMINAL_ID}/device-link"
    refute last_call[:headers].key?('Idempotency-Key')
    @manage.close_terminal_device_link(TERMINAL_ID, { rowVersion: 2, reasonCode: 'REMOVED' }, idempotency_key: KEY)
    assert_route 'POST', "/terminals/#{TERMINAL_ID}/device-link/close"
    assert_equal KEY, last_call[:headers]['Idempotency-Key']
    assert_nothing_sent do
      assert_raises(Lunixi::ConfigurationError) do
        @manage.add_terminal_acquirer(TERMINAL_ID, { vendorAcquirerRef: 'a', merchantNumber: 'm', terminalNumber: 't' })
      end
      assert_raises(Lunixi::ConfigurationError) do
        @manage.add_terminal_acquirer(TERMINAL_ID, { vendorAcquirerRef: 'a', merchantNumber: 'm', terminalNumber: 't', currencies: ['TRY', ''] })
      end
      assert_raises(Lunixi::ConfigurationError) { @manage.create_terminal({ code: 'T1', displayName: 'Front' }, idempotency_key: 'short') }
    end
  end

  def test_devices_and_identity
    @answers << response(201, { 'data' => { 'device' => { 'deviceId' => DEVICE_ID } } })
    created = @manage.create_device({ vendorCode: 'VENDOR', deviceModelId: 'dm_1', serialNumber: 'SN-1', integrationChannel: 'CLOUD' })
    assert_route 'POST', '/devices'
    assert_equal [201, DEVICE_ID], [created.status_code, created['device']['deviceId']]
    @manage.assign_device(DEVICE_ID, { rowVersion: 1, storeId: STORE_ID, registerId: nil, reasonCode: 'INSTALL' })
    assert_route 'POST', "/devices/#{DEVICE_ID}/assignment"
    assert_equal({ 'rowVersion' => 1, 'storeId' => STORE_ID, 'registerId' => nil, 'reasonCode' => 'INSTALL' }, sent_body)
    @answers << response(200, { 'data' => { 'device' => { 'deviceId' => DEVICE_ID }, 'closedAssignment' => { 'id' => 'as_1' } } })
    closed = @manage.close_device_assignment(DEVICE_ID, { rowVersion: 2, reasonCode: 'STORAGE' })
    assert_route 'POST', "/devices/#{DEVICE_ID}/assignment/close"
    assert_equal [200, 'as_1'], [closed.status_code, closed['closedAssignment']['id']]
    @manage.change_device_lifecycle(DEVICE_ID, { rowVersion: 3, target: 'SUSPENDED', reasonCode: 'MAINTENANCE' })
    assert_route 'POST', "/devices/#{DEVICE_ID}/lifecycle"
    @manage.retire_device(DEVICE_ID, { rowVersion: 4, reasonCode: 'BROKEN' }, idempotency_key: KEY)
    assert_route 'POST', "/devices/#{DEVICE_ID}/retire"
    @manage.revoke_device_key(DEVICE_ID, 'key_1', { rowVersion: 1, reasonCode: 'DEVICE_LOST' })
    assert_route 'POST', "/devices/#{DEVICE_ID}/keys/key_1/revoke"
    @manage.revert_device_enrollment(DEVICE_ID, 'key_1', { reasonCode: 'NOT_MY_DEVICE' })
    assert_route 'POST', "/devices/#{DEVICE_ID}/keys/key_1/revert-enrollment"
    @manage.revoke_activation_code(DEVICE_ID, { reasonCode: 'MERCHANT_REVOKED' })
    assert_route 'POST', "/devices/#{DEVICE_ID}/activation-code/revoke"
    assert_equal({ 'reasonCode' => 'MERCHANT_REVOKED' }, sent_body)
    assert_nothing_sent do
      assert_raises(Lunixi::ConfigurationError) { @manage.revoke_device_key(DEVICE_ID, 'key_1', { reasonCode: 'DEVICE_LOST' }) }
      assert_raises(Lunixi::ConfigurationError) { @manage.create_device({ vendorCode: 'VENDOR', deviceModelId: 'dm_1', serialNumber: 'SN-1' }) }
      assert_raises(Lunixi::PhysicalPosCardDataRejectedError) { @manage.update_device(DEVICE_ID, { rowVersion: 1, pinBlock: 'x' }) }
    end
  end

  def test_reads_unwrap_records
    @answers << response(200, { 'data' => { 'overview' => { 'storeCount' => 2 } } })
    assert_equal 2, @manage.get_overview['storeCount']
    assert_route 'GET', '/overview'
    @answers << response(200, { 'data' => { 'device' => { 'deviceId' => DEVICE_ID } } })
    assert_equal DEVICE_ID, @manage.get_device(DEVICE_ID)['deviceId']
    @answers << response(200, { 'data' => { 'store' => { 'storeId' => STORE_ID }, 'assignedDeviceCount' => 1 } })
    assert_equal 1, @manage.get_store(STORE_ID)['assignedDeviceCount']
    @answers << response(200, { 'data' => [{ 'vendorCode' => 'VENDOR' }] })
    assert_equal 'VENDOR', @manage.list_vendors.first['vendorCode']
    @manage.list_device_models(vendorCode: 'VENDOR', deviceType: 'ANDROID')
    assert_equal ["#{BASE}/catalog/device-models", 'vendorCode=VENDOR&deviceType=ANDROID'], [last_call[:uri].path, last_call[:uri].query]
    @manage.list_acquirers
    assert_route 'GET', '/catalog/acquirers'
  end

  def test_lists_pages_and_filters
    @answers << response(200, { 'data' => { 'items' => [{ 'deviceId' => DEVICE_ID }] }, 'pageInfo' => { 'hasMore' => false, 'totalCount' => 1 } })
    page = @manage.list_devices(storeId: STORE_ID, includeTotal: true, q: 'front')
    assert_equal [1, false, 1], [page.items.size, page.has_more, page.total_count]
    assert_equal 'includeTotal=true&storeId=st_1&q=front', last_call[:uri].query
    @manage.list_store_audit(STORE_ID, limit: 10)
    assert_equal ["#{BASE}/stores/#{STORE_ID}/audit", 'limit=10'], [last_call[:uri].path, last_call[:uri].query]
    @manage.list_terminal_links(TERMINAL_ID, cursor: 'c_1')
    assert_route 'GET', "/terminals/#{TERMINAL_ID}/links"
    @manage.list_device_keys(DEVICE_ID)
    assert_route 'GET', "/devices/#{DEVICE_ID}/keys"
    assert_nothing_sent do
      assert_raises(Lunixi::ConfigurationError) { @manage.list_store_audit(STORE_ID, includeTotal: true) }
      assert_raises(Lunixi::ConfigurationError) { @manage.list_registers(STORE_ID, q: 'x') }
      assert_raises(Lunixi::PhysicalPosCardDataRejectedError) { @manage.list_stores(q: '4111 1111 1111 1111') }
      assert_raises(Lunixi::ConfigurationError) { @manage.list_terminal_acquirers(TERMINAL_ID, status: 'ACTIVE') }
    end
  end

  def test_iterate_registers_follows_the_cursor
    @answers << response(200, { 'data' => { 'items' => [{ 'id' => 'r1' }] }, 'pageInfo' => { 'hasMore' => true, 'nextCursor' => 'c_2' } })
    @answers << response(200, { 'data' => { 'items' => [{ 'id' => 'r2' }] }, 'pageInfo' => { 'hasMore' => true, 'nextCursor' => '' } })
    seen = []
    @manage.iterate_registers(STORE_ID, status: 'ACTIVE') { |register| seen << register['id'] }
    assert_equal %w[r1 r2], seen
    assert_equal(['status=ACTIVE', 'cursor=c_2&status=ACTIVE'], gateway_calls.map { |call| call[:uri].query })
  end

  def test_settlement_policies
    policy = { mode: 'SCHEDULED', scheduleTime: '23:30', timeZone: 'Europe/Istanbul', scheduleDays: %w[MON TUE], retryWindowMinutes: 60,
               expectedRowVersion: 3 }
    @answers << response(200, { 'data' => { 'policy' => { 'mode' => 'SCHEDULED', 'rowVersion' => 4 } } })
    assert_equal 4, @manage.set_account_settlement_policy(policy)['rowVersion']
    assert_route 'PUT', '/settlement-policy'
    @manage.set_store_settlement_policy(STORE_ID, { mode: 'MANUAL' })
    assert_route 'PUT', "/stores/#{STORE_ID}/settlement-policy"
    @manage.set_device_settlement_policy(DEVICE_ID, { mode: 'DEVICE_AUTO' })
    assert_route 'PUT', "/devices/#{DEVICE_ID}/settlement-policy"
    @manage.clear_store_settlement_policy(STORE_ID, 4)
    assert_route 'DELETE', "/stores/#{STORE_ID}/settlement-policy"
    assert_equal ['expectedRowVersion=4', nil], [last_call[:uri].query, last_call[:body]]
    @manage.clear_account_settlement_policy
    assert_nil last_call[:uri].query
    @manage.clear_device_settlement_policy(DEVICE_ID)
    assert_route 'DELETE', "/devices/#{DEVICE_ID}/settlement-policy"
    @manage.get_account_settlement_policy
    assert_route 'GET', '/settlement-policy'
    @manage.get_store_settlement_policy(STORE_ID)
    @manage.get_device_settlement_policy(DEVICE_ID)
    @answers << response(200, { 'data' => { 'effective' => { 'sourceScopeType' => 'STORE' } } })
    assert_equal 'STORE', @manage.get_effective_settlement_policy(DEVICE_ID)['sourceScopeType']
    assert_route 'GET', "/devices/#{DEVICE_ID}/settlement-policy/effective"
    assert_nothing_sent do
      assert_raises(Lunixi::ConfigurationError) { @manage.set_account_settlement_policy({ scheduleTime: '23:30' }) }
      assert_raises(Lunixi::ConfigurationError) { @manage.set_account_settlement_policy({ mode: 'MANUAL', retryWindowMinutes: '60' }) }
      assert_raises(Lunixi::ConfigurationError) { @manage.clear_store_settlement_policy(STORE_ID, 0) }
    end
  end

  def test_keyed_write_errors_carry_the_key
    @answers << response(409, { 'code' => 'physical_pos.idempotency_mismatch' })
    error = assert_raises(Lunixi::ApiError) { @manage.create_store({ code: 'IST-01', name: 'Kadikoy' }, idempotency_key: KEY) }
    assert_equal [409, 'physical_pos.idempotency_mismatch', KEY], [error.status, error.code, error.idempotency_key]
    3.times { @answers << response(429, { 'code' => 'RATE_LIMITED' }, { 'retry-after' => '2' }) } # a read keeps the client's retries
    assert_equal 2, assert_raises(Lunixi::PhysicalPosRateLimitError) { @manage.list_stores }.retry_after
  end
end
