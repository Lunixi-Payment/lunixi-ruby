# frozen_string_literal: true

require_relative 'test_helper'

# Identity signal calls go through IDENTITY_ROUTES with the access token only. Ids are synthetic.
class IdentityTest < Minitest::Test
  def setup
    @answer = { 'success' => true, 'data' => { 'traceId' => 'tr_1', 'analysisStatus' => 'COMPLETED', 'riskFlags' => [] } }
    @transport = RecordingTransport.new { response(200, @answer) }
    @identity = client(transport: @transport).identity
  end

  def test_routes_are_bearer_only
    Lunixi::IDENTITY_ROUTES.each do |name, route|
      refute route['stepUp'], name
      assert_match %r{\A/api/v1/identity/live-sessions}, route['path'], name
    end
  end

  def test_analyze_sync_sends_the_signal_body
    result = @identity.analyze_sync({ subject_type: 'USER', subjectId: 'usr_1', device: { fingerprintId: 'fp_1' }, paymentId: 'pay_1' })
    assert_equal 'tr_1', result['traceId']
    call = api_calls(@transport).fetch(0)
    assert_equal ['POST', '/api/v1/identity/live-sessions/analyze-sync'], [call[:method], call[:uri].path]
    refute call[:headers].key?('X-Signature')
    assert_equal({ 'subjectType' => 'USER', 'subjectId' => 'usr_1', 'device' => { 'fingerprintId' => 'fp_1' }, 'paymentId' => 'pay_1' },
                 sent_json(call))
  end

  def test_local_errors_send_nothing
    [
      -> { @identity.analyze({ subjectType: 'USER' }) },
      -> { @identity.analyze({ device: 'fp_1' }) },
      -> { @identity.analyze({ deviceFingerprint: 'fp_1' }) },
      -> { @identity.analyze('fp_1') },
      -> { @identity.list_sessions(email: 'x') },
      -> { @identity.account_links('') }
    ].each { |call| assert_raises(Lunixi::ConfigurationError) { call.call } }
    assert_empty api_calls(@transport)
  end

  def test_account_links_detect_a_shared_device
    @answer = { 'success' => true, 'data' => { 'linkedAccounts' => [{ 'accountKeyHash' => 'h_1' }],
                                               'sessions' => [{ 'linkReasons' => %w[same_fingerprint same_device_cluster] },
                                                              { 'linkReasons' => %w[same_fingerprint] }] } }
    links = @identity.account_links('tr_1')
    assert Lunixi::Identity.device_shared?(links)
    refute Lunixi::Identity.device_shared?(links, 3)
    refute Lunixi::Identity.device_shared?({ 'linkedAccounts' => [] })
    assert_equal %w[same_fingerprint same_device_cluster], Lunixi::Identity.link_reasons(links)
    assert_equal '/api/v1/identity/live-sessions/tr_1/account-links', api_calls(@transport).fetch(0)[:uri].path
  end

  def test_reads_and_lists
    @identity.get_session('tr_1')
    @identity.related_sessions('tr_1', limit: 5)
    @identity.timeline('tr_1')
    @identity.top_sources(days: 7, limit: 10)
    @answer = { 'success' => true, 'data' => [{ 'traceId' => 'tr_1' }], 'pageInfo' => { 'nextCursor' => 'c_2', 'hasMore' => true } }
    page = @identity.list_sessions(fingerprint_id: 'fp_1', limit: 20)
    session, related, timeline, sources, list = api_calls(@transport)
    assert_equal '/api/v1/identity/live-sessions/tr_1', session[:uri].path
    assert_equal ['/api/v1/identity/live-sessions/tr_1/related-sessions', 'limit=5'], [related[:uri].path, related[:uri].query]
    assert_equal '/api/v1/identity/live-sessions/tr_1/timeline', timeline[:uri].path
    assert_equal ['/api/v1/identity/live-sessions/top-sources', 'days=7&limit=10'], [sources[:uri].path, sources[:uri].query]
    assert_equal ['/api/v1/identity/live-sessions', 'fingerprintId=fp_1&limit=20'], [list[:uri].path, list[:uri].query]
    assert_equal 'c_2', page.next_cursor
    assert_equal 'tr_1', page.items.first['traceId']
  end
end
