# frozen_string_literal: true

require_relative 'test_helper'

# KYC calls go through KYC_ROUTES with the access token only. Ids, names and the document are synthetic.
class KycTest < Minitest::Test
  def setup
    @answer = { 'success' => true, 'data' => { 'session' => { 'id' => 'ks_1', 'status' => 'CREATED' } } }
    @transport = RecordingTransport.new { response(200, @answer) }
    @kyc = client(transport: @transport).kyc
  end

  def test_routes_are_bearer_only_under_kyc
    Lunixi::KYC_ROUTES.each do |name, route|
      refute route['stepUp'], name
      assert_match %r{\A/api/v1/kyc/}, route['path'], name
    end
  end

  def test_create_session_maps_person_and_metadata_and_sends_the_key_twice
    session = @kyc.create_session({ subject_id: 'usr_1', sessionType: 'kyc', externalCustomerId: 'usr_1', person: { firstName: 'Test' },
                                    metadata: { orderId: 'ord_1' }, ttlMinutes: 60 }, idempotency_key: 'idem-kyc-1')
    assert_equal 'ks_1', session['session']['id']
    call = api_calls(@transport).fetch(0)
    assert_equal ['POST', '/api/v1/kyc/sessions'], [call[:method], call[:uri].path]
    refute call[:headers].key?('X-Signature')
    assert_equal 'idem-kyc-1', call[:headers]['Idempotency-Key']
    assert_equal({ 'subjectId' => 'usr_1', 'sessionType' => 'KYC', 'externalCustomerId' => 'usr_1', 'ttlMinutes' => 60,
                   'idempotencyKey' => 'idem-kyc-1', 'customer' => { 'customerType' => 'PERSON', 'firstName' => 'Test' },
                   'evidenceContextJson' => '{"orderId":"ord_1"}' }, sent_json(call))
  end

  def test_local_errors_send_nothing
    base = { subjectId: 'usr_1', sessionType: 'KYC' }
    [
      -> { @kyc.create_session(base.merge(sessionType: 'AML')) },
      -> { @kyc.create_session(base.merge(person: { firstName: 'A' }, company: { legalName: 'B' })) },
      -> { @kyc.create_session(base.merge(ttlMinutes: 0)) },
      -> { @kyc.create_session(base.merge(ttlMinutes: 1441)) },
      -> { @kyc.create_session(base.merge(requiredDocumentTypes: 'PASSPORT')) },
      -> { @kyc.create_session(base.merge(metadata: { a: 1 }, evidenceContextJson: '{}')) },
      -> { @kyc.create_session(base.merge(nickname: 'x')) },
      -> { @kyc.create_session({ sessionType: 'KYC' }) },
      -> { @kyc.list_sessions(status: 'APPROVED') },
      -> { @kyc.set_jurisdiction('ks_1', ' ') },
      -> { @kyc.upload_document('ks_1', { documentType: 'PASSPORT', mimeType: 'image/png' }) }
    ].each { |call| assert_raises(Lunixi::ConfigurationError) { call.call } }
    assert_empty api_calls(@transport)
  end

  def test_list_sessions_maps_page_size_and_page_token
    @answer = { 'success' => true, 'data' => { 'items' => [{ 'id' => 'ks_1' }], 'pageInfo' => { 'nextCursor' => 'c_2', 'hasMore' => true } } }
    page = @kyc.list_sessions(pageSize: 10, pageToken: 'c_1')
    assert_equal 'limit=10&cursor=c_1', api_calls(@transport).fetch(0)[:uri].query
    assert_equal 'c_2', page.next_cursor
    assert page.has_more?
  end

  def test_a_page_info_without_a_cursor_is_the_last_page
    @answer = { 'success' => true, 'data' => { 'items' => [], 'pageInfo' => { 'nextCursor' => nil }, 'nextCursor' => 'stale' } }
    page = @kyc.list_sessions
    assert_nil page.next_cursor
    refute page.has_more?
  end

  def test_session_operations_and_admin_routes
    @kyc.set_primary_document('ks_1', 'PASSPORT')
    @kyc.submit('ks_1')
    @kyc.manual_review('ks_1', reason_code: 'DOC_UNCLEAR')
    @kyc.evidence_request({ subjectId: 'usr_1', sessionType: 'EVIDENCE', evidencePurpose: 'PROOF_OF_ADDRESS' })
    @kyc.rotate_webhook_secret
    @kyc.webhook_outbox(limit: 5, status: 'FAILED')
    @kyc.retry_webhook_event('evt_1')
    document, submit, review, evidence, rotate, outbox, retry_event = api_calls(@transport)
    assert_equal({ 'documentType' => 'PASSPORT' }, sent_json(document))
    assert_equal '/api/v1/kyc/sessions/ks_1/primary-document', document[:uri].path
    assert_nil submit[:body]
    assert_equal({ 'reasonCode' => 'DOC_UNCLEAR' }, sent_json(review))
    assert_equal '/api/v1/kyc/evidence-requests', evidence[:uri].path
    assert_equal '/api/v1/kyc/admin/merchant-policy/webhook-secret/rotate', rotate[:uri].path
    assert_equal 'limit=5&status=FAILED', outbox[:uri].query
    assert_equal '/api/v1/kyc/admin/webhook-outbox/evt_1/retry', retry_event[:uri].path
  end

  def test_upload_document_never_echoes_the_image
    image = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
    error = assert_raises(Lunixi::ConfigurationError) do
      @kyc.upload_document('ks_1', { documentType: 'PASSPORT', fileBase64: image, mimeType: 'image/png', faceImage: image })
    end
    assert_match(/faceImage/, error.message)
    refute_includes error.message, image
    assert_empty api_calls(@transport)
  end

  def test_assurance_and_terminal_helpers
    assert Lunixi::Kyc.assurance_meets?('high', Lunixi::KycAssuranceLevel::SUBSTANTIAL)
    refute Lunixi::Kyc.assurance_meets?('LOW', 'SUBSTANTIAL')
    assert Lunixi::Kyc.assurance_meets?('NONE', 'NOT_PERFORMED')
    assert_equal 0, Lunixi::Kyc.assurance_rank(nil)
    assert Lunixi::Kyc.session_terminal?('approved')
    refute Lunixi::Kyc.session_terminal?('PROCESSING')
  end
end
