# frozen_string_literal: true

module Lunixi
  # Identity (device and account-linking signals) routes (/api/v1/identity). The browser fingerprint SDK
  # uses the publishable key (/identity/sdk/init), which is not here.

  # Body of analyze / analyze_sync; the nested objects are forwarded as given.
  IDENTITY_ANALYZE_FIELDS = %w[subjectType subjectId productContext integrationMode customer device session source account metadata
                               paymentId].freeze

  identity_live = '/api/v1/identity/live-sessions'
  route = lambda do |method, path, **extra|
    RouteRequest.route(method, path, step_up: false, idempotency_key: 'none', **extra)
  end

  # Every identity route the SDK calls (access token only). The same table as the Node SDK's
  # IDENTITY_ROUTES; the parity test compares it with the shared catalog.
  IDENTITY_ROUTES = {
    'analyzeSync' => route.call('POST', "#{identity_live}/analyze-sync", optional: IDENTITY_ANALYZE_FIELDS),
    'analyze' => route.call('POST', "#{identity_live}/analyze", optional: IDENTITY_ANALYZE_FIELDS),
    'accountLinks' => route.call('GET', "#{identity_live}/:traceId/account-links"),
    'getSession' => route.call('GET', "#{identity_live}/:traceId"),
    'relatedSessions' => route.call('GET', "#{identity_live}/:traceId/related-sessions", query: %w[limit]),
    'timeline' => route.call('GET', "#{identity_live}/:traceId/timeline"),
    'topSources' => route.call('GET', "#{identity_live}/top-sources", query: %w[days limit]),
    'listSessions' => route.call('GET', identity_live, query: %w[fingerprintId deviceId paymentId limit])
  }.freeze
end
