# frozen_string_literal: true

module Lunixi
  # KYC / KYB / evidence sessions (/api/v1/kyc, client.kyc).
  #
  # Calls carry the access token only (no per-request signature). Your server creates the session
  # (externalCustomerId = your own user id, echoed on every webhook); the browser SDK then runs the
  # capture with the publishable key. The kyc.* webhook is the authority for the verification result.
  #
  # Bodies and filters are checked against KYC_ROUTES before anything is sent; an error names the field,
  # never its value (a document image never appears in an error). Keys are the wire names (String or
  # Symbol; snake_case works too).
  #
  # Session calls return the envelope's data ({ session, capturePolicy, ... }; no personal data comes
  # back, only status, decision, risk and the achieved assurance). Lists return a Lunixi::ListPage.
  class Kyc
    SESSION_LIST_FILTERS = %w[limit cursor pageSize pageToken].freeze

    # True for APPROVED, REJECTED, MANUAL_REVIEW, EXPIRED, ABANDONED and CANCELLED (case-insensitive).
    def self.session_terminal?(status)
      status.is_a?(String) && KycSessionStatus::TERMINAL_STATES.include?(status.upcase)
    end

    # Rank on the assurance ladder: HIGH 3, SUBSTANTIAL 2, LOW 1, anything else 0.
    def self.assurance_rank(level)
      { KycAssuranceLevel::HIGH => 3, KycAssuranceLevel::SUBSTANTIAL => 2, KycAssuranceLevel::LOW => 1 }
        .fetch(level.is_a?(String) ? level.upcase : '', 0)
    end

    # True when achieved meets or exceeds required.
    def self.assurance_meets?(achieved, required)
      assurance_rank(achieved) >= assurance_rank(required)
    end

    def initialize(client)
      @routes = RouteTable.new(client, KYC_ROUTES)
    end

    # { subjectId, sessionType, externalCustomerId?, customerMode?, person? | company? | customer?,
    # jurisdiction?, requiredDocumentTypes?, primaryDocumentType?, evidencePurpose?, ttlMinutes?,
    # metadata? }. person / company are sent as customer with customerType PERSON / COMPANY; metadata is
    # sent as evidenceContextJson. An Idempotency-Key (idempotency_key: or the request's idempotencyKey)
    # goes in the header and the body.
    def create_session(request, idempotency_key: nil)
      body, key = session_body('createSession', request, idempotency_key)
      @routes.data('createSession', body: body, idempotency_key: key)
    end

    def get_session(session_id)
      @routes.data('getSession', params: { 'sessionId' => session_id })
    end

    # Filters: limit, cursor (pageSize / pageToken are read as the same). Anything else is refused: the
    # merchant list has no status or customer filter, and dropping one would return every session.
    def list_sessions(**filters)
      given = RouteRequest.wire_keys!(filters, SESSION_LIST_FILTERS, 'listSessions', 'filter')
      query = RouteRequest.compact('limit' => given.fetch('limit', given['pageSize']), 'cursor' => given.fetch('cursor', given['pageToken']))
      @routes.page('listSessions', query: query)
    end

    def iterate_sessions(**filters, &block)
      RouteRequest.each_item(filters, block) { |query| list_sessions(**query) }
    end

    # Applicant jurisdiction (ISO country) on a server-created session.
    def set_jurisdiction(session_id, jurisdiction)
      @routes.data('setJurisdiction', params: { 'sessionId' => session_id },
                                      body: { 'jurisdiction' => RouteRequest.text!(jurisdiction, 'jurisdiction') })
    end

    # PASSPORT, NATIONAL_ID, DRIVERS_LICENSE or RESIDENCE_PERMIT.
    def set_primary_document(session_id, document_type)
      @routes.data('setPrimaryDocument', params: { 'sessionId' => session_id },
                                         body: { 'documentType' => RouteRequest.text!(document_type, 'documentType') })
    end

    # Server-side document upload (most flows use the browser SDK): { documentType, fileBase64, mimeType,
    # side?, jurisdiction?, metadataJson?, idempotencyKey? }. The image never appears in an error message.
    def upload_document(session_id, document)
      raise ConfigurationError, 'uploadDocument document must be a Hash.' unless document.is_a?(Hash)

      @routes.data('uploadDocument', params: { 'sessionId' => session_id }, body: document)
    end

    # The session's event timeline (audit).
    def timeline(session_id)
      @routes.data('timeline', params: { 'sessionId' => session_id })
    end

    def submit(session_id)
      @routes.data('submit', params: { 'sessionId' => session_id })
    end

    def manual_review(session_id, reason_code: nil, reason_detail: nil)
      body = RouteRequest.compact('reasonCode' => RouteRequest.optional_text(reason_code, 'reasonCode'),
                                  'reasonDetail' => RouteRequest.optional_text(reason_detail, 'reasonDetail'))
      @routes.data('manualReview', params: { 'sessionId' => session_id }, body: body)
    end

    # An EVIDENCE session (proof-of-X), optionally linked to a payment or order; the same body as
    # create_session.
    def evidence_request(request, idempotency_key: nil)
      body, key = session_body('evidenceRequest', request, idempotency_key)
      @routes.data('evidenceRequest', body: body, idempotency_key: key)
    end

    # Your KYC policy (required assurance, providers ...).
    def merchant_policy
      @routes.data('merchantPolicy')
    end

    def update_merchant_policy(policy)
      @routes.data('updateMerchantPolicy', body: policy)
    end

    # Rotates the KYC webhook signing secret.
    def rotate_webhook_secret
      @routes.data('rotateWebhookSecret')
    end

    # KYC webhook deliveries; filters limit, status.
    def webhook_outbox(**filters)
      @routes.page('webhookOutbox', query: filters)
    end

    def retry_webhook_event(event_id)
      @routes.data('retryWebhookEvent', params: { 'eventId' => event_id })
    end

    # Data erasure requests; filters limit, status.
    def erasure_requests(**filters)
      @routes.page('erasureRequests', query: filters)
    end

    def inspect
      '#<Lunixi::Kyc>'
    end

    private

    def session_body(name, request, idempotency_key)
      body = RouteRequest.wire_hash!(request, "#{name} request")
      person = body.delete('person')
      company = body.delete('company')
      metadata = body.delete('metadata')
      key = RouteTable.idempotency_key_of(name, body, idempotency_key)
      body['idempotencyKey'] = key.strip if key.is_a?(String) && !key.strip.empty?
      body['sessionType'] = RouteRequest.one_of!(body['sessionType'].to_s.upcase, KycSessionType::ALL, 'sessionType') if body.key?('sessionType')
      customer!(name, body, person, company)
      evidence_context!(name, body, metadata)
      check_session_fields!(body)
      [body, key]
    end

    def customer!(name, body, person, company)
      given = [person, company, body['customer']].compact
      raise ConfigurationError, "#{name} takes one of person, company or customer." if given.length > 1

      body['customer'] = { 'customerType' => 'PERSON' }.merge(nested!(person, 'person')) unless person.nil?
      body['customer'] = { 'customerType' => 'COMPANY' }.merge(nested!(company, 'company')) unless company.nil?
    end

    def evidence_context!(name, body, metadata)
      return if metadata.nil?
      raise ConfigurationError, "#{name} takes metadata or evidenceContextJson, not both." if body.key?('evidenceContextJson')

      body['evidenceContextJson'] = JsonBody.dump(nested!(metadata, 'metadata'))
    end

    def check_session_fields!(body)
      if body.key?('ttlMinutes')
        ttl = body['ttlMinutes']
        unless ttl.is_a?(Integer) && ttl.between?(1, KYC_SESSION_TTL_MAX_MINUTES)
          raise ConfigurationError, "'ttlMinutes' must be an integer from 1 to #{KYC_SESSION_TTL_MAX_MINUTES}."
        end
      end
      types = body['requiredDocumentTypes']
      return if types.nil? || (types.is_a?(Array) && types.all? { |type| type.is_a?(String) })

      raise ConfigurationError, "'requiredDocumentTypes' must be an array of document types."
    end

    def nested!(value, field)
      raise ConfigurationError, "'#{field}' must be a Hash." unless value.is_a?(Hash)

      value.transform_keys(&:to_s)
    end
  end
end
