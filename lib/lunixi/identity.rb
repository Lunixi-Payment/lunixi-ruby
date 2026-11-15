# frozen_string_literal: true

module Lunixi
  # Identity signals (/api/v1/identity, client.identity).
  #
  # Calls carry the access token only. The browser fingerprint SDK produces a traceId; your server reads
  # the linked accounts of that trace and flags or blocks when the device is shared ("one person, many
  # accounts", Lunixi::Identity.device_shared?).
  #
  # This is a signal surface: it carries risk flags, reason codes, similarity probabilities and the
  # identity snapshot, not an allow / review / block verdict (that is the fraud decision). Bodies and
  # filters are checked against IDENTITY_ROUTES before anything is sent. Calls return the envelope's data;
  # list_sessions returns a Lunixi::ListPage.
  class Identity
    NESTED_FIELDS = %w[customer device session source account metadata].freeze

    # True when the device of an account_links answer is shared by at least threshold accounts, counting
    # the current one (linkedAccounts excludes it). With the default 2, a second account on the device
    # trips it.
    def self.device_shared?(account_links, threshold = 2)
      linked = account_links.is_a?(Hash) && account_links['linkedAccounts'].is_a?(Array) ? account_links['linkedAccounts'].length : 0
      linked + 1 >= [2, threshold].max
    end

    # The distinct linkReasons of an account_links answer's sessions (same_device_cluster,
    # same_fingerprint ...).
    def self.link_reasons(account_links)
      sessions = account_links.is_a?(Hash) && account_links['sessions'].is_a?(Array) ? account_links['sessions'] : []
      sessions.flat_map { |session| session.is_a?(Hash) && session['linkReasons'].is_a?(Array) ? session['linkReasons'] : [] }
              .map(&:to_s).uniq
    end

    def initialize(client)
      @routes = RouteTable.new(client, IDENTITY_ROUTES)
    end

    # Synchronous analysis: { subjectType?, subjectId?, productContext?, integrationMode?, customer?,
    # device?, session?, source?, account?, metadata?, paymentId? }. Returns { traceId, analysisStatus,
    # riskFlags, reasonCodes, identitySnapshot, ... }.
    def analyze_sync(request)
      @routes.data('analyzeSync', body: analyze_body(request))
    end

    # Queues the analysis and returns the traceId at once.
    def analyze(request)
      @routes.data('analyze', body: analyze_body(request))
    end

    # Other accounts seen on this device / fingerprint / IP (account keys hashed).
    def account_links(trace_id)
      @routes.data('accountLinks', params: { 'traceId' => trace_id })
    end

    def get_session(trace_id)
      @routes.data('getSession', params: { 'traceId' => trace_id })
    end

    # Recent sessions of the same device-identity cluster.
    def related_sessions(trace_id, limit: nil)
      @routes.data('relatedSessions', params: { 'traceId' => trace_id }, query: RouteRequest.compact('limit' => limit))
    end

    # The session summary and its recorded lifecycle events.
    def timeline(trace_id)
      @routes.data('timeline', params: { 'traceId' => trace_id })
    end

    # Source domains ranked by repeated risky activity; filters days, limit.
    def top_sources(**filters)
      @routes.data('topSources', query: filters)
    end

    # Filters: fingerprintId, deviceId, paymentId, limit.
    def list_sessions(**filters)
      @routes.page('listSessions', query: filters)
    end

    def inspect
      '#<Lunixi::Identity>'
    end

    private

    def analyze_body(request)
      body = RouteRequest.wire_hash!(request, 'analyze request')
      NESTED_FIELDS.each do |field|
        raise ConfigurationError, "'#{field}' must be a Hash." if body.key?(field) && !body[field].is_a?(Hash)
      end
      raise ConfigurationError, 'subjectType and subjectId go together.' unless body.key?('subjectType') == body.key?('subjectId')

      body
    end
  end
end
