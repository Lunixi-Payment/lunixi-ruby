# frozen_string_literal: true

module Lunixi
  # Sanctions screening values and routes (/api/v1/sanction, product SANCTION_SERVICE).

  # Risk domains a screening can be narrowed to (riskDomains). Omitted: every domain.
  module SanctionRiskDomain
    SANCTIONS = 'sanctions'
    PEP = 'pep'
    RCA = 'rca'
    WANTED = 'wanted'
    REGULATORY = 'regulatory'
    DEBARMENT = 'debarment'
    OWNERSHIP = 'ownership'
    VESSEL = 'vessel'
    SECURITIES = 'securities'
    ALL = [SANCTIONS, PEP, RCA, WANTED, REGULATORY, DEBARMENT, OWNERSHIP, VESSEL, SECURITIES].freeze
  end

  # Name-screening presets. Sent with riskDomains, their intersection is screened.
  module SanctionScreenMode
    SANCTIONS_ONLY = 'sanctions_only'
    SANCTIONS_PEP = 'sanctions_pep'
    FULL_RISK = 'full_risk'
    ALL = [SANCTIONS_ONLY, SANCTIONS_PEP, FULL_RISK].freeze
  end

  # Wallet-screening depth; the wider modes add exposure and crypto-intelligence hits.
  module SanctionWalletScreenMode
    WALLET_SANCTIONS = 'wallet_sanctions'
    WALLET_RISK = 'wallet_risk'
    WALLET_FULL_AML = 'wallet_full_aml'
    ALL = [WALLET_SANCTIONS, WALLET_RISK, WALLET_FULL_AML].freeze
  end

  module SanctionSubjectType
    PERSON = 'person'
    ORGANIZATION = 'organization'
    ALL = [PERSON, ORGANIZATION].freeze
  end

  # How much of the requested scope a screening covered. COMPLETE: every requested risk domain was
  # screened. PARTIAL: some requested domain has no list (uncoveredRiskDomains, uncoveredSources); no
  # match is clear only for what was screened. DEGRADED: the candidate search was limited; screen again.
  module SanctionCoverageStatus
    COMPLETE = 'COMPLETE'
    PARTIAL = 'PARTIAL'
    DEGRADED = 'DEGRADED'
    ALL = [COMPLETE, PARTIAL, DEGRADED].freeze
  end

  module SanctionHitType
    EXACT = 'exact'
    PROBABLE = 'probable'
    POSSIBLE = 'possible'
    ALL = [EXACT, PROBABLE, POSSIBLE].freeze
  end

  sanction_page = %w[limit cursor].freeze

  # Every sanction route an API key can reach: method, path, whether it is a screening (the answer must
  # be status: "success" to be read), the body fields the gateway forwards (required / optional / anyOf:
  # at least one of them present) and the query parameters. The same table as the Node SDK's
  # SANCTION_ROUTES; the parity test compares it with the shared catalog. The gateway passes the body to
  # the sanction service, which silently drops an unknown field, so the SDK refuses one before sending.
  SANCTION_ROUTES = {
    'screenName' => RouteRequest.route('POST', '/api/v1/sanction/screening/name',
                                       screening: true, required: %w[name],
                                       optional: %w[subjectType country dateOfBirth identifiers riskDomains mode threshold customerReference]),
    'screenWallet' => RouteRequest.route('POST', '/api/v1/sanction/screening/wallet',
                                         screening: true, required: %w[walletAddress], optional: %w[chain mode customerReference]),
    'screenAccount' => RouteRequest.route('POST', '/api/v1/sanction/screening/account',
                                          screening: true, required: %w[accountValue accountScheme],
                                          optional: %w[providerCode productChannel customerReference]),
    # Neither parties nor accounts: the sanction service holds the transaction as not screenable.
    'screenTransaction' => RouteRequest.route('POST', '/api/v1/sanction/screening/transaction',
                                              screening: true, required: [],
                                              optional: %w[transactionType direction amount currency channel occurredAt parties accounts metadataJson],
                                              any_of: %w[parties accounts]),
    'screenPublicProcurementBan' => RouteRequest.route('POST', '/api/v1/sanction/intelligence/public-procurement-ban',
                                                       screening: true, required: [],
                                                       optional: %w[entityName tckn vkn entityType onlyActive limit customerReference productChannel],
                                                       any_of: %w[entityName tckn vkn]),
    'screenAdverseMedia' => RouteRequest.route('POST', '/api/v1/sanction/intelligence/adverse-media',
                                               screening: true, required: [],
                                               optional: %w[entityName entityType tckn vkn countryCode limit onlyActive customerReference productChannel]),
    'evaluateBehavioralAlert' => RouteRequest.route('POST', '/api/v1/sanction/intelligence/behavioral-alert',
                                                    screening: true, required: [],
                                                    optional: %w[subjectReference customerReference productChannel velocityScore unusualPattern
                                                                 countryRiskLevel metadataJson]),
    'listScreeningHistory' => RouteRequest.route('GET', '/api/v1/sanction/screening/history', screening: false, query: sanction_page),

    'registerMonitoring' => RouteRequest.route('POST', '/api/v1/sanction/monitoring/register',
                                               screening: false, required: %w[externalCustomerId],
                                               optional: %w[subjectType profileJson frequency riskDomainScope]),
    'listMonitoringAlerts' => RouteRequest.route('GET', '/api/v1/sanction/monitoring/alerts',
                                                 screening: false, query: %w[status] + sanction_page + %w[includeTotal]),
    'listMonitoredEntities' => RouteRequest.route('GET', '/api/v1/sanction/monitoring/entities',
                                                  screening: false, query: %w[activeOnly] + sanction_page + %w[includeTotal]),
    'listMonitoringMatches' => RouteRequest.route('GET', '/api/v1/sanction/monitoring/matches', screening: false, query: %w[status] + sanction_page),
    'getDatasetFreshness' => RouteRequest.route('GET', '/api/v1/sanction/monitoring/dataset-freshness', screening: false),

    'searchEntities' => RouteRequest.route('GET', '/api/v1/sanction/intelligence/entity-search', screening: false, query: %w[q limit]),
    'getEntityProfile' => RouteRequest.route('GET', '/api/v1/sanction/intelligence/entity-profiles/:entityId', screening: false, query: %w[screeningRequestId]),
    'getEntityGraph' => RouteRequest.route('GET', '/api/v1/sanction/intelligence/entity-graph/:entityId', screening: false, query: %w[depth]),
    'getIndirectExposure' => RouteRequest.route('GET', '/api/v1/sanction/intelligence/indirect-exposure/:entityId',
                                                screening: false, query: %w[maxDepth entityIds]),
    'getOwnershipAggregation' => RouteRequest.route('GET', '/api/v1/sanction/intelligence/ownership-aggregation/:entityId',
                                                    screening: false, query: %w[depth entityIds]),

    'listBlacklistEntries' => RouteRequest.route('GET', '/api/v1/sanction/blacklist', screening: false, query: sanction_page)
  }.freeze

  # Fields of the nested lists, checked element by element ("route.field").
  SANCTION_NESTED_FIELDS = {
    'screenName.identifiers' => { 'required' => %w[type value].freeze, 'optional' => [].freeze }.freeze,
    'screenTransaction.parties' => {
      'required' => %w[name].freeze, 'optional' => %w[role subjectType countryCode customerId dateOfBirth nationalId].freeze
    }.freeze,
    'screenTransaction.accounts' => { 'required' => %w[accountType value].freeze, 'optional' => %w[role providerCode chain].freeze }.freeze
  }.freeze

  # Value sets checked before sending ("route.field"); the sanction service refuses anything else with 400.
  SANCTION_VALUE_SETS = {
    'screenName.riskDomains' => SanctionRiskDomain::ALL,
    'screenName.mode' => SanctionScreenMode::ALL,
    'screenName.subjectType' => SanctionSubjectType::ALL,
    'screenWallet.mode' => SanctionWalletScreenMode::ALL,
    'registerMonitoring.subjectType' => SanctionSubjectType::ALL,
    'registerMonitoring.riskDomainScope' => SanctionRiskDomain::ALL
  }.freeze
end
