# frozen_string_literal: true

require_relative 'test_helper'

# Sanction calls go through SANCTION_ROUTES with the access token only; a screening is read only when it
# ran ("success") and is clear only under the clean-read rule. Names and ids are synthetic.
class SanctionTest < Minitest::Test
  def setup
    @transport = RecordingTransport.new { response(200, { 'status' => 'success', 'data' => { 'matches' => [], 'coverageStatus' => 'COMPLETE' } }) }
    @sanction = client(transport: @transport).sanction
  end

  def test_screen_name_is_unsigned_and_checked
    result = @sanction.screen_name(name: 'Test Person', risk_domains: %w[sanctions pep], mode: 'sanctions_pep',
                                   identifiers: [{ type: 'NATIONAL_ID', value: '00000000000' }])
    call = api_calls(@transport).fetch(0)
    assert_equal ['POST', '/api/v1/sanction/screening/name'], [call[:method], call[:uri].path]
    assert_equal 'Bearer at_TEST_synthetic', call[:headers]['Authorization']
    refute call[:headers].key?('X-Signature')
    assert_equal({ 'name' => 'Test Person', 'riskDomains' => %w[sanctions pep], 'mode' => 'sanctions_pep',
                   'identifiers' => [{ 'type' => 'NATIONAL_ID', 'value' => '00000000000' }] }, sent_json(call))
    assert Lunixi::Sanction.clear_screening?(result)
  end

  def test_local_errors_send_nothing
    [
      -> { @sanction.screen_name(name: 'X', nickname: 'Y') },
      -> { @sanction.screen_name(subjectType: 'person') },
      -> { @sanction.screen_name(name: 'X', riskDomains: %w[sanctions crypto]) },
      -> { @sanction.screen_name(name: 'X', identifiers: [{ type: 'TCKN' }]) },
      -> { @sanction.screen_wallet(walletAddress: '0xabc', mode: 'full_risk') },
      -> { @sanction.screen_transaction(amount: '100', currency: 'TRY') },
      -> { @sanction.screen_transaction(parties: []) },
      -> { @sanction.screen_transaction(parties: [{ role: 'payer' }]) },
      -> { @sanction.screen_public_procurement_ban(onlyActive: true) },
      -> { @sanction.register_monitoring(externalCustomerId: 'c_1', profile: { name: 'X' }, profileJson: '{}') },
      -> { @sanction.list_monitoring_alerts(severity: 'high') },
      -> { @sanction.get_entity_graph('') }
    ].each { |call| assert_raises(Lunixi::ConfigurationError) { call.call } }
    assert_empty api_calls(@transport)
  end

  def test_any_of_is_satisfied_by_one_group_member
    @sanction.screen_public_procurement_ban(vkn: '0000000000')
    @sanction.screen_transaction(accounts: [{ accountType: 'IBAN', value: 'TR000000000000000000000000' }])
    assert_equal 2, api_calls(@transport).size
  end

  def test_register_monitoring_sends_profile_as_json
    @sanction.register_monitoring(externalCustomerId: 'c_1', profile: { name: 'Test Person', country: 'TR' })
    assert_equal({ 'externalCustomerId' => 'c_1', 'profileJson' => '{"name":"Test Person","country":"TR"}' }, sent_json(api_calls(@transport).fetch(0)))
  end

  def test_entity_reads_join_entity_ids
    @sanction.get_indirect_exposure('ent_1', max_depth: 2, entity_ids: %w[ent_1 ent_2])
    call = api_calls(@transport).fetch(0)
    assert_equal '/api/v1/sanction/intelligence/indirect-exposure/ent_1', call[:uri].path
    assert_equal({ 'maxDepth' => '2', 'entityIds' => 'ent_1,ent_2' }, URI.decode_www_form(call[:uri].query).to_h)
  end

  def test_a_screening_that_did_not_run_raises
    transport = RecordingTransport.new { response(200, { 'status' => 'failure', 'statusCode' => 503, 'code' => 'sanction.screen_name.failed' }) }
    error = assert_raises(Lunixi::ApiError) { client(transport: transport).sanction.screen_name(name: 'X') }
    assert_equal 503, error.status
    assert_equal 'sanction.screen_name.failed', error.code
    transport = RecordingTransport.new { response(503, { 'status' => 'failure', 'code' => 'sanction.screen_name.failed' }) }
    assert_raises(Lunixi::ApiError) { client(transport: transport).sanction.screen_name(name: 'X') }
    assert_equal 1, api_calls(transport).size
  end

  def test_clean_read_rule
    clear = Lunixi::Sanction.method(:clear_screening?)
    assert clear.call({ 'matches' => [], 'coverageStatus' => 'COMPLETE' })
    assert clear.call({ 'hits' => [] }) # account screening: no coverage reported
    refute clear.call({ 'matches' => [], 'coverageStatus' => 'PARTIAL' })
    refute clear.call({ 'matches' => [], 'coverageStatus' => 'DEGRADED' })
    refute clear.call({ 'matches' => [], 'coverageStatus' => nil })
    refute clear.call({ 'matches' => [{ 'entityId' => 'e' }], 'coverageStatus' => 'COMPLETE' })
    refute clear.call({ 'publicationHits' => [{}], 'coverageStatus' => 'COMPLETE' })
    refute clear.call({ 'isSanctioned' => true })
    refute clear.call({ 'caseRequired' => true, 'coverageStatus' => 'COMPLETE' })
    refute clear.call({ 'decision' => 'REVIEW' })
    refute clear.call(nil)
  end

  def test_lists_read_the_cursor
    transport = RecordingTransport.new { response(200, { 'status' => 'success', 'data' => { 'items' => [{ 'id' => 's_1' }], 'nextCursor' => 'c2' } }) }
    page = client(transport: transport).sanction.list_screening_history(limit: 10)
    assert_equal 'c2', page.next_cursor
    assert page.has_more?
  end
end
