# frozen_string_literal: true

module Lunixi
  # KYC / KYB / evidence values and routes (/api/v1/kyc). The same codes as the Node and PHP SDKs. The
  # browser bootstraps its own SDK token with the publishable key (/kyc/sdk/init); that route is not
  # reachable from a server key and is not here.

  # Session types. EVIDENCE is proof-of-X (address, funds, card ownership ...), not only onboarding.
  module KycSessionType
    # A person's identity.
    KYC = 'KYC'
    # A company and its beneficial owners.
    KYB = 'KYB'
    EVIDENCE = 'EVIDENCE'
    ALL = [KYC, KYB, EVIDENCE].freeze
  end

  # Session status.
  module KycSessionStatus
    CREATED = 'CREATED'
    INITIATED = 'INITIATED'
    DOCUMENT_SUBMITTED = 'DOCUMENT_SUBMITTED'
    PROCESSING = 'PROCESSING'
    AWAITING_PROVIDER_CALLBACK = 'AWAITING_PROVIDER_CALLBACK'
    AWAITING_ADDITIONAL_DOCUMENT = 'AWAITING_ADDITIONAL_DOCUMENT'
    AWAITING_USER_ACTION = 'AWAITING_USER_ACTION'
    UNDER_REVIEW = 'UNDER_REVIEW'
    PENDING_ADDITIONAL_INFO = 'PENDING_ADDITIONAL_INFO'
    RESCREEN_REQUIRED = 'RESCREEN_REQUIRED'
    REOPENED = 'REOPENED'
    APPROVED = 'APPROVED'
    REJECTED = 'REJECTED'
    MANUAL_REVIEW = 'MANUAL_REVIEW'
    EXPIRED = 'EXPIRED'
    ABANDONED = 'ABANDONED'
    CANCELLED = 'CANCELLED'
    ALL = [CREATED, INITIATED, DOCUMENT_SUBMITTED, PROCESSING, AWAITING_PROVIDER_CALLBACK, AWAITING_ADDITIONAL_DOCUMENT, AWAITING_USER_ACTION,
           UNDER_REVIEW, PENDING_ADDITIONAL_INFO, RESCREEN_REQUIRED, REOPENED, APPROVED, REJECTED, MANUAL_REVIEW, EXPIRED, ABANDONED,
           CANCELLED].freeze
    TERMINAL_STATES = [APPROVED, REJECTED, MANUAL_REVIEW, EXPIRED, ABANDONED, CANCELLED].freeze
  end

  KYC_SESSION_TERMINAL_STATES = KycSessionStatus::TERMINAL_STATES

  # evidencePurpose of an EVIDENCE session.
  module KycEvidencePurpose
    IDENTITY_VERIFICATION = 'IDENTITY_VERIFICATION'
    BUSINESS_VERIFICATION = 'BUSINESS_VERIFICATION'
    PROOF_OF_FUNDS = 'PROOF_OF_FUNDS'
    PROOF_OF_ADDRESS = 'PROOF_OF_ADDRESS'
    SOURCE_OF_FUNDS = 'SOURCE_OF_FUNDS'
    SOURCE_OF_WEALTH = 'SOURCE_OF_WEALTH'
    TRANSACTION_EVIDENCE = 'TRANSACTION_EVIDENCE'
    CARD_OWNERSHIP = 'CARD_OWNERSHIP'
    PAYMENT_METHOD_OWNERSHIP = 'PAYMENT_METHOD_OWNERSHIP'
    PAYOUT_EVIDENCE = 'PAYOUT_EVIDENCE'
    MERCHANT_ONBOARDING = 'MERCHANT_ONBOARDING'
    ALL = [IDENTITY_VERIFICATION, BUSINESS_VERIFICATION, PROOF_OF_FUNDS, PROOF_OF_ADDRESS, SOURCE_OF_FUNDS, SOURCE_OF_WEALTH, TRANSACTION_EVIDENCE,
           CARD_OWNERSHIP, PAYMENT_METHOD_OWNERSHIP, PAYOUT_EVIDENCE, MERCHANT_ONBOARDING].freeze
  end

  # Assurance ladder (rank-aligned with NIST 800-63 IAL / eIDAS LoA). A gate passes when achieved >=
  # required (Lunixi::Kyc.assurance_meets?).
  module KycAssuranceLevel
    NONE = 'NONE'
    NOT_PERFORMED = 'NOT_PERFORMED'
    LOW = 'LOW'
    SUBSTANTIAL = 'SUBSTANTIAL'
    HIGH = 'HIGH'
    ALL = [NONE, NOT_PERFORMED, LOW, SUBSTANTIAL, HIGH].freeze
  end

  # Domains of the achieved assurance snapshot (session.decision.assuranceSnapshot.achieved), each an
  # assurance level.
  module KycAssuranceDomain
    IDENTITY = 'identity_evidence_strength'
    DOCUMENT = 'document_authenticity_level'
    BIOMETRIC = 'possession_biometric_binding'
    AUTHORITATIVE = 'authoritative_source_level'
    ADDRESS = 'address_assurance'
    AML = 'aml_freshness'
    HUMAN_REVIEW = 'human_review_level'
    ALL = [IDENTITY, DOCUMENT, BIOMETRIC, AUTHORITATIVE, ADDRESS, AML, HUMAN_REVIEW].freeze
  end

  # Webhook event types (the same signed envelope as payment events). data always carries sessionId and
  # externalCustomerId; terminal events carry the decision. A rescreen or a screening hit on an approved
  # session must revoke access.
  module KycEvents
    SESSION_CREATED = 'kyc.session.created'
    SESSION_INITIATED = 'kyc.session.initiated'
    SESSION_EXPIRED = 'kyc.session.expired'
    SESSION_ABANDONED = 'kyc.session.abandoned'
    SESSION_CANCELLED = 'kyc.session.cancelled'
    DOCUMENT_RECEIVED = 'kyc.document.received'
    DOCUMENT_REJECTED = 'kyc.document.rejected'
    LIVENESS_COMPLETED = 'kyc.liveness.completed'
    PROCESSING_STARTED = 'kyc.processing.started'
    MANUAL_REVIEW_REQUIRED = 'kyc.manual_review.required'
    APPROVED = 'kyc.approved'
    REJECTED = 'kyc.rejected'
    RESCREEN_REQUIRED = 'kyc.rescreen.required'
    KYB_SESSION_CREATED = 'kyb.session.created'
    KYB_COMPANY_VERIFIED = 'kyb.company.verified'
    KYB_COMPANY_NOT_FOUND = 'kyb.company.not_found'
    KYB_UBO_PENDING = 'kyb.ubo.pending'
    KYB_RELATED_KYC_REQUIRED = 'kyb.related_kyc.required'
    KYB_RELATED_KYC_COMPLETED = 'kyb.related_kyc.completed'
    KYB_MANUAL_REVIEW_REQUIRED = 'kyb.manual_review.required'
    KYB_APPROVED = 'kyb.approved'
    KYB_REJECTED = 'kyb.rejected'
    SCREENING_MATCH_DETECTED = 'screening.match.detected'
    SCREENING_FALSE_POSITIVE_CLEARED = 'screening.false_positive.cleared'
    MONITORING_ALERT_CREATED = 'ongoing_monitoring.alert.created'
    ALL = [SESSION_CREATED, SESSION_INITIATED, SESSION_EXPIRED, SESSION_ABANDONED, SESSION_CANCELLED, DOCUMENT_RECEIVED, DOCUMENT_REJECTED,
           LIVENESS_COMPLETED, PROCESSING_STARTED, MANUAL_REVIEW_REQUIRED, APPROVED, REJECTED, RESCREEN_REQUIRED, KYB_SESSION_CREATED,
           KYB_COMPANY_VERIFIED, KYB_COMPANY_NOT_FOUND, KYB_UBO_PENDING, KYB_RELATED_KYC_REQUIRED, KYB_RELATED_KYC_COMPLETED,
           KYB_MANUAL_REVIEW_REQUIRED, KYB_APPROVED, KYB_REJECTED, SCREENING_MATCH_DETECTED, SCREENING_FALSE_POSITIVE_CLEARED,
           MONITORING_ALERT_CREATED].freeze
  end

  KYC_EVENT_TYPES = KycEvents::ALL

  # Longest session lifetime ttlMinutes accepts (one day).
  KYC_SESSION_TTL_MAX_MINUTES = 1440

  kyc_base = '/api/v1/kyc'
  session_fields = %w[externalCustomerId customerMode customer jurisdiction requiredDocumentTypes primaryDocumentType evidencePurpose ttlMinutes
                      idempotencyKey evidenceContextJson].freeze
  route = lambda do |method, path, **extra|
    RouteRequest.route(method, path, **{ step_up: false, idempotency_key: 'none' }.merge(extra))
  end

  # Every KYC route the SDK calls (access token only). The same table as the Node SDK's KYC_ROUTES; the
  # parity test compares it with the shared catalog.
  KYC_ROUTES = {
    'createSession' => route.call('POST', "#{kyc_base}/sessions", idempotency_key: 'optional', required: %w[subjectId sessionType],
                                                                 optional: session_fields),
    'getSession' => route.call('GET', "#{kyc_base}/sessions/:sessionId"),
    # The merchant list takes only these two; an unknown filter is a 400 on the gateway.
    'listSessions' => route.call('GET', "#{kyc_base}/sessions", query: %w[limit cursor]),
    'setJurisdiction' => route.call('POST', "#{kyc_base}/sessions/:sessionId/jurisdiction", required: %w[jurisdiction]),
    'setPrimaryDocument' => route.call('POST', "#{kyc_base}/sessions/:sessionId/primary-document", required: %w[documentType]),
    'uploadDocument' => route.call('POST', "#{kyc_base}/sessions/:sessionId/documents", required: %w[documentType fileBase64 mimeType],
                                                                                        optional: %w[side jurisdiction metadataJson idempotencyKey]),
    'timeline' => route.call('GET', "#{kyc_base}/sessions/:sessionId/timeline"),
    'submit' => route.call('POST', "#{kyc_base}/sessions/:sessionId/submit"),
    'manualReview' => route.call('POST', "#{kyc_base}/sessions/:sessionId/manual-review", optional: %w[reasonCode reasonDetail], optional_body: true),
    'evidenceRequest' => route.call('POST', "#{kyc_base}/evidence-requests", idempotency_key: 'optional', required: %w[subjectId sessionType],
                                                                            optional: session_fields),
    'merchantPolicy' => route.call('GET', "#{kyc_base}/admin/merchant-policy"),
    'updateMerchantPolicy' => route.call('POST', "#{kyc_base}/admin/merchant-policy", free: true),
    'rotateWebhookSecret' => route.call('POST', "#{kyc_base}/admin/merchant-policy/webhook-secret/rotate"),
    'webhookOutbox' => route.call('GET', "#{kyc_base}/admin/webhook-outbox", query: %w[limit status]),
    'retryWebhookEvent' => route.call('POST', "#{kyc_base}/admin/webhook-outbox/:eventId/retry"),
    'erasureRequests' => route.call('GET', "#{kyc_base}/admin/erasure-requests", query: %w[limit status])
  }.freeze
end
