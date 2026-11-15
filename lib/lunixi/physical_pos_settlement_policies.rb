# frozen_string_literal: true

module Lunixi
  # End-of-day policy routes of PhysicalPosManagement (account → store → device). Mixed into
  # PhysicalPosManagement; uses its request and path helpers.
  #
  # A level's policy replaces the level above it entirely. set_* sends the full setting: { mode
  # (MANUAL | SCHEDULED | DEVICE_AUTO), scheduleTime?, timeZone?, scheduleDays?, retryWindowMinutes?,
  # retryIntervalMinutes?, offlineBehavior?, overdueAlertHours?, expectedRowVersion? }. clear_* resets
  # the account to MANUAL, or removes a store / device override (it then inherits).
  # expectedRowVersion is the policy's rowVersion you read (409 physical_pos.version_conflict when it
  # changed); leave it out for last write wins. Each call returns the policy.
  module PhysicalPosSettlementPolicies
    def get_account_settlement_policy # rubocop:disable Naming/AccessorMethodName
      @gateway.record('GET', '/settlement-policy', 'policy')
    end

    def set_account_settlement_policy(request) # rubocop:disable Naming/AccessorMethodName
      @gateway.record('PUT', '/settlement-policy', 'policy', body: settlement_policy(request))
    end

    def clear_account_settlement_policy(expected_row_version = nil)
      @gateway.record('DELETE', '/settlement-policy', 'policy', query: expected_row_version_query(expected_row_version))
    end

    def get_store_settlement_policy(store_id)
      @gateway.record('GET', "#{store_path(store_id)}/settlement-policy", 'policy')
    end

    def set_store_settlement_policy(store_id, request)
      @gateway.record('PUT', "#{store_path(store_id)}/settlement-policy", 'policy', body: settlement_policy(request))
    end

    def clear_store_settlement_policy(store_id, expected_row_version = nil)
      @gateway.record('DELETE', "#{store_path(store_id)}/settlement-policy", 'policy', query: expected_row_version_query(expected_row_version))
    end

    def get_device_settlement_policy(device_id)
      @gateway.record('GET', "#{device_path(device_id)}/settlement-policy", 'policy')
    end

    # DEVICE_AUTO only on devices that report their end-of-day results.
    def set_device_settlement_policy(device_id, request)
      @gateway.record('PUT', "#{device_path(device_id)}/settlement-policy", 'policy', body: settlement_policy(request))
    end

    def clear_device_settlement_policy(device_id, expected_row_version = nil)
      @gateway.record('DELETE', "#{device_path(device_id)}/settlement-policy", 'policy', query: expected_row_version_query(expected_row_version))
    end

    # The policy a device follows (GET /devices/{deviceId}/settlement-policy/effective): { deviceId,
    # sourceScopeType (ACCOUNT | STORE | DEVICE), policy, serverSettlementSupported, deviceAutoSupported,
    # nextScheduledAt, lastSettlementAt, overdue, scheduleWarning }.
    def get_effective_settlement_policy(device_id)
      @gateway.record('GET', "#{device_path(device_id)}/settlement-policy/effective", 'effective')
    end

    private

    def settlement_policy(request)
      body(request, 'setSettlementPolicy')
    end

    # DELETE …/settlement-policy?expectedRowVersion= (left out when nil).
    def expected_row_version_query(expected_row_version)
      return {} if expected_row_version.nil?

      { 'expectedRowVersion' => PhysicalPosRequest.row_version!(expected_row_version, 'expectedRowVersion').to_s }
    end
  end
end
