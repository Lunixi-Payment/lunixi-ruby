# frozen_string_literal: true

module Lunixi
  # Device identity routes of PhysicalPosManagement (physical_pos:identity for writes). Mixed into
  # PhysicalPosManagement; uses its request and path helpers.
  module PhysicalPosDeviceIdentity
    # The device's identity keys, fingerprints only (GET /devices/{deviceId}/keys). Each key: keyId,
    # algorithm, keyStatus (ACTIVE | SUPERSEDED | REVOKED), enrolledVia (PAIRING | ACTIVATION_CODE |
    # ROTATION), fingerprint, lineageRootKeyId, rotatedFromKeyId, activatedAt, supersededAt, revokedAt,
    # revokeReason, rowVersion.
    def list_device_keys(device_id, **filters)
      @gateway.page("#{device_path(device_id)}/keys", query(filters, 'history'))
    end

    def iterate_device_keys(device_id, **filters, &block)
      PhysicalPosResponses.each_item(filters, block) { |page| list_device_keys(device_id, **page) }
    end

    # Revokes a device key: { rowVersion (the key's), reasonCode }; reasonCode DEVICE_LOST,
    # DEVICE_STOLEN, KEY_COMPROMISED, DEVICE_REPLACED, MERCHANT_REQUEST or OTHER.
    # { 'key', 'lifecycleStatus', 'replayed' }.
    def revoke_device_key(device_id, key_id, request)
      @gateway.data('POST', "#{key_path(device_id, key_id)}/revoke", body: body(request, 'revokeDeviceKey'))
    end

    # Reverts an activation-code enrollment (revokes the key, suspends the device): { reasonCode };
    # NOT_MY_DEVICE, SUSPECTED_PHISHING, WRONG_DEVICE or OTHER. { 'key', 'lifecycleStatus', 'replayed' }.
    def revert_device_enrollment(device_id, key_id, request)
      @gateway.data('POST', "#{key_path(device_id, key_id)}/revert-enrollment", body: body(request, 'revertDeviceEnrollment'))
    end

    # Revokes the device's open activation code: { reasonCode }; MERCHANT_REVOKED, DEVICE_LOST,
    # DEVICE_STOLEN or OTHER. { 'deviceId', 'revokedAt', 'revokeReason' }.
    def revoke_activation_code(device_id, request)
      @gateway.data('POST', "#{device_path(device_id)}/activation-code/revoke", body: body(request, 'revokeActivationCode'))
    end

    private

    def key_path(device_id, key_id)
      "#{device_path(device_id)}/keys/#{id(key_id, 'keyId')}"
    end
  end
end
