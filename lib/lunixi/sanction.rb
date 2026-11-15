# frozen_string_literal: true

module Lunixi
  # Sanctions screening (/api/v1/sanction/*, product SANCTION_SERVICE).
  #
  # Calls carry the access token minted from your API key; these routes take no per-request signature.
  # The key needs the sanction:view_results permission (403 otherwise).
  #
  # Screening returns matches, not verdicts: the decision is yours. Read a result with
  # Lunixi::Sanction.clear_screening?(result): an empty match list is clear only when coverageStatus is
  # COMPLETE. When the screening cannot run the gateway answers 503 (ApiError); a 2xx answer whose status
  # is not "success" raises ApiError too. It never comes back as an empty result.
  #
  # Bodies and filters are checked against SANCTION_ROUTES before anything is sent: an unknown field, a
  # missing required field, an empty anyOf group, a malformed nested row or a value outside its set
  # (SANCTION_VALUE_SETS) raises ConfigurationError. Keys are the wire names (snake_case works too).
  #
  # Answers are the envelope's data. The envelope's requestId is the HTTP request's id; the screening's
  # own id is data.screeningRequestId (name screening). Lists return a Lunixi::ListPage.
  class Sanction
    BLOCKING_DECISIONS = %w[block blocked reject rejected review hit escalate].freeze

    # Whether a screening answer (the data a screen_* method returned) can be read as "nothing found":
    # no match or hit of any kind, no listed or blocking flag, no blocking decision, and, when it reports
    # coverage, coverageStatus COMPLETE. PARTIAL, DEGRADED or a nil coverage is never clear. Account and
    # adverse-media screening report no coverage; for them the hits and flags decide.
    def self.clear_screening?(result)
      return false unless result.is_a?(Hash)
      return false if %w[matches hits publicationHits].any? { |key| result[key].is_a?(Array) && !result[key].empty? }
      return false if %w[isSanctioned isBlacklisted matched caseRequired].any? { |key| result[key] == true }
      return false if result['decision'].is_a?(String) && BLOCKING_DECISIONS.include?(result['decision'].downcase)
      return result['coverageStatus'] == SanctionCoverageStatus::COMPLETE if result.key?('coverageStatus')

      true
    end

    def initialize(client)
      @client = client
    end

    # Person or organization: { name, subjectType?, country?, dateOfBirth?, identifiers?, riskDomains?,
    # mode?, threshold?, customerReference? }.
    def screen_name(request)
      screening('screenName', request)
    end

    # Crypto wallet address (exact match against the listed addresses).
    def screen_wallet(request)
      screening('screenWallet', request)
    end

    # Bank account / IBAN against your own deny list and account risk data (no list publication).
    def screen_account(request)
      screening('screenAccount', request)
    end

    # Every party and account of a transaction, against one list publication.
    def screen_transaction(request)
      screening('screenTransaction', request)
    end

    # Public procurement debarment lists, by name and TCKN / VKN. A list that is not published makes
    # coverageStatus PARTIAL and is named in uncoveredSources: no match is not a clean result for it.
    def screen_public_procurement_ban(request)
      screening('screenPublicProcurementBan', request)
    end

    # Adverse media. Runs only when your adverse-media policy is enabled.
    def screen_adverse_media(request)
      screening('screenAdverseMedia', request)
    end

    # Behavioural risk signal evaluation.
    def evaluate_behavioral_alert(request)
      screening('evaluateBehavioralAlert', request)
    end

    # Earlier screenings (audit trail), newest first.
    def list_screening_history(**filters)
      page('listScreeningHistory', filters)
    end

    def iterate_screening_history(**filters, &block)
      RouteResponse.each_item(filters, block) { |query| list_screening_history(**query) }
    end

    # Registers a subject for ongoing monitoring; returns { monitoredEntityId }. A profile Hash (name,
    # dateOfBirth, country, identifiers ...) is sent as profileJson; pass one of the two.
    def register_monitoring(request = {})
      raise ConfigurationError, 'registerMonitoring request must be a Hash.' unless request.is_a?(Hash)

      profile_key = request.keys.find { |key| key.to_s == 'profile' }
      body = request
      unless profile_key.nil?
        body = request.reject { |key, _| key == profile_key }
        if body.keys.any? { |key| %w[profileJson profile_json].include?(key.to_s) }
          raise ConfigurationError, 'registerMonitoring takes profile or profileJson, not both.'
        end

        body = body.merge('profileJson' => JsonBody.dump(request[profile_key]))
      end
      RouteResponse.unwrap(invoke('registerMonitoring', body: body))
    end

    # New-match alerts raised by monitoring; status narrows (e.g. open).
    def list_monitoring_alerts(**filters)
      page('listMonitoringAlerts', filters)
    end

    def iterate_monitoring_alerts(**filters, &block)
      RouteResponse.each_item(filters, block) { |query| list_monitoring_alerts(**query) }
    end

    # Monitored subjects; activeOnly defaults to true on the gateway.
    def list_monitored_entities(**filters)
      page('listMonitoredEntities', filters)
    end

    def iterate_monitored_entities(**filters, &block)
      RouteResponse.each_item(filters, block) { |query| list_monitored_entities(**query) }
    end

    # Matches raised by monitoring.
    def list_monitoring_matches(**filters)
      page('listMonitoringMatches', filters)
    end

    def iterate_monitoring_matches(**filters, &block)
      RouteResponse.each_item(filters, block) { |query| list_monitoring_matches(**query) }
    end

    # Freshness of the source lists: { manifest }. A manifest that could not be produced raises ApiError.
    def get_dataset_freshness # rubocop:disable Naming/AccessorMethodName -- catalog operation getDatasetFreshness
      checked(invoke('getDatasetFreshness'))
    end

    # Entity search by name: q, limit.
    def search_entities(**filters)
      RouteResponse.unwrap(invoke('searchEntities', query: filters))
    end

    # Entity risk profile; screening_request_id reads it on that screening's publication.
    def get_entity_profile(entity_id, screening_request_id: nil)
      entity('getEntityProfile', entity_id, 'screeningRequestId' => screening_request_id)
    end

    # Relationship graph, depth 1–3.
    def get_entity_graph(entity_id, depth: nil)
      entity('getEntityGraph', entity_id, 'depth' => depth)
    end

    # Indirect exposure paths; entity_ids are the records of a merged match (sent comma-separated).
    def get_indirect_exposure(entity_id, max_depth: nil, entity_ids: nil)
      entity('getIndirectExposure', entity_id, 'maxDepth' => max_depth, 'entityIds' => id_list(entity_ids))
    end

    # Ownership aggregation (50% rule); entity_ids are the records of a merged match.
    def get_ownership_aggregation(entity_id, depth: nil, entity_ids: nil)
      entity('getOwnershipAggregation', entity_id, 'depth' => depth, 'entityIds' => id_list(entity_ids))
    end

    # Your own deny-list entries (read only with an API key).
    def list_blacklist_entries(**filters)
      page('listBlacklistEntries', filters)
    end

    def iterate_blacklist_entries(**filters, &block)
      RouteResponse.each_item(filters, block) { |query| list_blacklist_entries(**query) }
    end

    def inspect
      '#<Lunixi::Sanction>'
    end

    private

    def screening(name, request)
      checked(invoke(name, body: request))
    end

    def page(name, filters)
      RouteResponse.page(invoke(name, query: filters))
    end

    def entity(name, entity_id, query)
      RouteResponse.unwrap(invoke(name, params: { 'entityId' => entity_id }, query: RouteRequest.compact(query)))
    end

    # Sends one route of SANCTION_ROUTES with the access token (no request signature).
    def invoke(name, params: {}, body: nil, query: nil)
      route = SANCTION_ROUTES.fetch(name)
      path = RouteRequest.path!(route['path'], params)
      filters = RouteRequest.query!(query, route['query'] || [], name)
      payload = route['method'] == 'GET' ? nil : body!(name, route, body || {})
      @client.request(route['method'], path, body: payload, query: filters, signed: false)
    end

    def body!(name, route, body)
      plain = RouteRequest.fields!(body, route['required'], route['optional'], name)
      if route['anyOf']&.none? { |key| RouteRequest.present?(plain[key]) }
        raise ConfigurationError, "#{name} requires at least one of #{route['anyOf'].join(', ')}."
      end

      plain.keys.each do |key|
        nested = SANCTION_NESTED_FIELDS["#{name}.#{key}"]
        plain[key] = rows!(plain[key], nested, "#{name}.#{key}") if nested
        allowed = SANCTION_VALUE_SETS["#{name}.#{key}"]
        values!(plain[key], allowed, "#{name}.#{key}") if allowed
      end
      plain
    end

    def rows!(rows, spec, label)
      raise ConfigurationError, "'#{label}' must be an array." unless rows.is_a?(Array)

      rows.each_with_index.map { |row, index| RouteRequest.fields!(row, spec['required'], spec['optional'], "#{label}[#{index}]") }
    end

    def values!(value, allowed, label)
      outside = Array(value).reject { |entry| allowed.include?(entry) }
      return if outside.empty?

      raise ConfigurationError, "'#{label}' must be one of #{allowed.join(', ')}."
    end

    # A 2xx answer that is not status "success" is refused rather than read: a screening that did not run
    # must never look like an empty result.
    def checked(response)
      if response.is_a?(Hash) && response['status'].is_a?(String) && response['status'] != 'success'
        status = response['statusCode'].is_a?(Integer) ? response['statusCode'] : 0
        raise ApiError.new(status: status, code: response['code'], request_id: response['requestId'], message: 'The screening did not complete.')
      end

      RouteResponse.unwrap(response)
    end

    def id_list(entity_ids)
      return nil if entity_ids.nil?

      ids = Array(entity_ids).map { |id| id.to_s.strip }.reject(&:empty?)
      ids.empty? ? nil : ids.join(',')
    end
  end
end
