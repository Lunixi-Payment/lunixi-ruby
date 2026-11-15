# frozen_string_literal: true

module Lunixi
  # Physical POS management: stores, registers, logical terminals with their bank rows, payment-provider
  # rows and device links, devices with their identity keys, the end-of-day policy, the catalog and the
  # overview (/api/v1/physical-pos). Reads need physical_pos:view, writes physical_pos:manage, device
  # identity writes (key revocation, enrollment revert, activation-code revocation)
  # physical_pos:identity; a TEST key can only read. Activation codes are issued in the panel only.
  #
  # Updates and status changes take the rowVersion you last read (409 physical_pos.version_conflict
  # when the record changed). Reason codes are closed sets checked by the gateway (400
  # physical_pos.input.reason_code_invalid). Routes that require an Idempotency-Key get a new UUID when
  # you pass nil; a key you pass is sent exactly as given (never trimmed; '' is refused). The key sent
  # comes back as idempotency_key. A key belongs to one operation: reusing it for another body or route
  # is 409 physical_pos.idempotency_mismatch.
  #
  # Lists return a PhysicalPosPage (items, has_more, next_cursor, total_count); total_count is filled
  # only with includeTotal: true on entity lists. Each list has an iterate_* twin that walks every page.
  # The device identity and end-of-day policy routes are in PhysicalPosDeviceIdentity and
  # PhysicalPosSettlementPolicies.
  class PhysicalPosManagement
    include PhysicalPosDeviceIdentity
    include PhysicalPosSettlementPolicies

    CREATED = ->(replayed) { replayed ? 200 : 201 }
    OK = ->(_replayed) { 200 }

    def initialize(gateway)
      @gateway = gateway
    end

    # Store, register, terminal and device counts (GET /overview).
    def get_overview # rubocop:disable Naming/AccessorMethodName
      @gateway.record('GET', '/overview', 'overview')
    end

    # ── Catalog ──────────────────────────────────────────────────────────────

    # Device vendors (GET /catalog/vendors).
    def list_vendors
      @gateway.data('GET', '/catalog/vendors')
    end

    # Device models; filters vendorCode, deviceType, status (GET /catalog/device-models).
    def list_device_models(**filters)
      @gateway.data('GET', '/catalog/device-models', query: query(filters, 'listDeviceModels'))
    end

    # Banks a terminal row can belong to (GET /catalog/acquirers).
    def list_acquirers
      @gateway.data('GET', '/catalog/acquirers')
    end

    # ── Stores ───────────────────────────────────────────────────────────────

    def list_stores(**filters)
      @gateway.page('/stores', query(filters, 'listStores'))
    end

    def iterate_stores(**filters, &block)
      PhysicalPosResponses.each_item(filters, block) { |page| list_stores(**page) }
    end

    # result['store']; 201 new / 200 replay.
    def create_store(request, idempotency_key: nil)
      @gateway.keyed_write('/stores', body(request, 'createStore'), idempotency_key, CREATED)
    end

    # { 'store', 'registerSummary' => { activeCount, archivedCount }, 'assignedDeviceCount' }.
    def get_store(store_id)
      @gateway.data('GET', store_path(store_id))
    end

    # nil clears city, district, addressLine, externalRef; a field left out is unchanged.
    def update_store(store_id, request)
      @gateway.record('PATCH', store_path(store_id), 'store', body: body(request, 'updateStore'))
    end

    # { 'store', 'archivedRegisterCount' }; the active registers are archived with it.
    def archive_store(store_id, request)
      @gateway.data('POST', "#{store_path(store_id)}/archive", body: status_change(request))
    end

    def restore_store(store_id, request)
      @gateway.record('POST', "#{store_path(store_id)}/restore", 'store', body: status_change(request))
    end

    def list_store_audit(store_id, **filters)
      @gateway.page("#{store_path(store_id)}/audit", query(filters, 'history'))
    end

    def iterate_store_audit(store_id, **filters, &block)
      PhysicalPosResponses.each_item(filters, block) { |page| list_store_audit(store_id, **page) }
    end

    # ── Registers ────────────────────────────────────────────────────────────

    def list_registers(store_id, **filters)
      @gateway.page("#{store_path(store_id)}/registers", query(filters, 'listRegisters'))
    end

    def iterate_registers(store_id, **filters, &block)
      PhysicalPosResponses.each_item(filters, block) { |page| list_registers(store_id, **page) }
    end

    # result['register']; 201 new / 200 replay.
    def create_register(store_id, request, idempotency_key: nil)
      path = "#{store_path(store_id)}/registers"
      @gateway.keyed_write(path, body(request, 'createRegister'), idempotency_key, CREATED)
    end

    def update_register(register_id, request)
      @gateway.record('PATCH', register_path(register_id), 'register', body: body(request, 'updateRegister'))
    end

    def archive_register(register_id, request)
      @gateway.record('POST', "#{register_path(register_id)}/archive", 'register', body: status_change(request))
    end

    def restore_register(register_id, request)
      @gateway.record('POST', "#{register_path(register_id)}/restore", 'register', body: status_change(request))
    end

    def list_register_audit(register_id, **filters)
      @gateway.page("#{register_path(register_id)}/audit", query(filters, 'history'))
    end

    def iterate_register_audit(register_id, **filters, &block)
      PhysicalPosResponses.each_item(filters, block) { |page| list_register_audit(register_id, **page) }
    end

    # ── Logical terminals ────────────────────────────────────────────────────

    def list_terminals(**filters)
      @gateway.page('/terminals', query(filters, 'listTerminals'))
    end

    def iterate_terminals(**filters, &block)
      PhysicalPosResponses.each_item(filters, block) { |page| list_terminals(**page) }
    end

    # result['terminal']; 201 new / 200 replay.
    def create_terminal(request, idempotency_key: nil)
      @gateway.keyed_write('/terminals', body(request, 'createTerminal'), idempotency_key, CREATED)
    end

    # { 'terminal', 'acquirers' => { items, pageInfo } }.
    def get_terminal(terminal_id)
      @gateway.data('GET', terminal_path(terminal_id))
    end

    def update_terminal(terminal_id, request)
      @gateway.record('PATCH', terminal_path(terminal_id), 'terminal', body: body(request, 'updateTerminal'))
    end

    def close_terminal(terminal_id, request)
      @gateway.record('POST', "#{terminal_path(terminal_id)}/close", 'terminal', body: status_change(request))
    end

    # Bank rows of a terminal; a row's id is the payment's terminalAcquirerId.
    def list_terminal_acquirers(terminal_id, **filters)
      @gateway.page("#{terminal_path(terminal_id)}/acquirers", query(filters, 'listTerminalAcquirers'))
    end

    def iterate_terminal_acquirers(terminal_id, **filters, &block)
      PhysicalPosResponses.each_item(filters, block) { |page| list_terminal_acquirers(terminal_id, **page) }
    end

    # result['acquirer']; 201 new / 200 replay.
    def add_terminal_acquirer(terminal_id, request, idempotency_key: nil)
      path = "#{terminal_path(terminal_id)}/acquirers"
      @gateway.keyed_write(path, body(request, 'addTerminalAcquirer'), idempotency_key, CREATED)
    end

    def update_terminal_acquirer(terminal_acquirer_id, request)
      path = "/terminal-acquirers/#{id(terminal_acquirer_id, 'terminalAcquirerId')}"
      @gateway.record('PATCH', path, 'acquirer', body: body(request, 'updateTerminalAcquirer'))
    end

    # Payment-provider rows of a terminal (e.g. a meal card provider's merchant / terminal / product
    # code). A row's id is the payment's terminalProviderId.
    def list_terminal_providers(terminal_id, **filters)
      @gateway.page("#{terminal_path(terminal_id)}/providers", query(filters, 'listTerminalProviders'))
    end

    def iterate_terminal_providers(terminal_id, **filters, &block)
      PhysicalPosResponses.each_item(filters, block) { |page| list_terminal_providers(terminal_id, **page) }
    end

    # Adds a provider row: { vendorAccountId, merchantCode, terminalCode, productCode?, label? }; the
    # provider comes from the vendor account. result['provider']; 201 new / 200 replay.
    def add_terminal_provider(terminal_id, request, idempotency_key: nil)
      path = "#{terminal_path(terminal_id)}/providers"
      @gateway.keyed_write(path, body(request, 'addTerminalProvider'), idempotency_key, CREATED)
    end

    # { rowVersion, label?, status? }; nil label clears it, status ACTIVE or DISABLED.
    def update_terminal_provider(terminal_provider_id, request)
      path = "/terminal-providers/#{id(terminal_provider_id, 'terminalProviderId')}"
      @gateway.record('PATCH', path, 'provider', body: body(request, 'updateTerminalProvider'))
    end

    # Links the terminal to a device (closing the previous link): { 'terminal', 'link' }.
    def change_terminal_device(terminal_id, request)
      @gateway.data('POST', "#{terminal_path(terminal_id)}/device-link", body: body(request, 'changeTerminalDevice'))
    end

    # result['terminal'] and result['link'] (the closed link or nil).
    def close_terminal_device_link(terminal_id, request, idempotency_key: nil)
      @gateway.keyed_write("#{terminal_path(terminal_id)}/device-link/close", status_change(request), idempotency_key, OK)
    end

    def list_terminal_links(terminal_id, **filters)
      @gateway.page("#{terminal_path(terminal_id)}/links", query(filters, 'history'))
    end

    def iterate_terminal_links(terminal_id, **filters, &block)
      PhysicalPosResponses.each_item(filters, block) { |page| list_terminal_links(terminal_id, **page) }
    end

    def list_terminal_audit(terminal_id, **filters)
      @gateway.page("#{terminal_path(terminal_id)}/audit", query(filters, 'history'))
    end

    def iterate_terminal_audit(terminal_id, **filters, &block)
      PhysicalPosResponses.each_item(filters, block) { |page| list_terminal_audit(terminal_id, **page) }
    end

    # ── Devices ──────────────────────────────────────────────────────────────

    def list_devices(**filters)
      @gateway.page('/devices', query(filters, 'listDevices'))
    end

    def iterate_devices(**filters, &block)
      PhysicalPosResponses.each_item(filters, block) { |page| list_devices(**page) }
    end

    # result['device']; 201 new / 200 replay.
    def create_device(request, idempotency_key: nil)
      @gateway.keyed_write('/devices', body(request, 'createDevice'), idempotency_key, CREATED)
    end

    def get_device(device_id)
      @gateway.record('GET', device_path(device_id), 'device')
    end

    def update_device(device_id, request)
      @gateway.record('PATCH', device_path(device_id), 'device', body: body(request, 'updateDevice'))
    end

    # Assigns the device to a store (and register): { 'device', 'assignment', 'previousAssignmentId' }.
    def assign_device(device_id, request)
      @gateway.data('POST', "#{device_path(device_id)}/assignment", body: body(request, 'assignDevice'))
    end

    # Moves the device to storage: result['device'] and result['closedAssignment'].
    def close_device_assignment(device_id, request, idempotency_key: nil)
      @gateway.keyed_write("#{device_path(device_id)}/assignment/close", status_change(request), idempotency_key, OK)
    end

    # target: ACTIVE, SUSPENDED or MAINTENANCE.
    def change_device_lifecycle(device_id, request)
      @gateway.record('POST', "#{device_path(device_id)}/lifecycle", 'device', body: body(request, 'changeDeviceLifecycle'))
    end

    # result['device']. Retirement is final.
    def retire_device(device_id, request, idempotency_key: nil)
      @gateway.keyed_write("#{device_path(device_id)}/retire", status_change(request), idempotency_key, OK)
    end

    def list_device_assignments(device_id, **filters)
      @gateway.page("#{device_path(device_id)}/assignments", query(filters, 'history'))
    end

    def iterate_device_assignments(device_id, **filters, &block)
      PhysicalPosResponses.each_item(filters, block) { |page| list_device_assignments(device_id, **page) }
    end

    def list_device_audit(device_id, **filters)
      @gateway.page("#{device_path(device_id)}/audit", query(filters, 'history'))
    end

    def iterate_device_audit(device_id, **filters, &block)
      PhysicalPosResponses.each_item(filters, block) { |page| list_device_audit(device_id, **page) }
    end

    def inspect
      '#<Lunixi::PhysicalPosManagement>'
    end

    private

    def body(request, operation)
      PhysicalPosRequest.body!(request, PHYSICAL_POS_REQUEST_FIELDS.fetch(operation), "#{operation} request")
    end

    def status_change(request)
      body(request, 'statusChange')
    end

    def query(filters, route)
      PhysicalPosFilters.query!(filters, route)
    end

    def id(value, field)
      PhysicalPosRequest.path_id(value, field)
    end

    def store_path(store_id)
      "/stores/#{id(store_id, 'storeId')}"
    end

    def register_path(register_id)
      "/registers/#{id(register_id, 'registerId')}"
    end

    def terminal_path(terminal_id)
      "/terminals/#{id(terminal_id, 'terminalId')}"
    end

    def device_path(device_id)
      "/devices/#{id(device_id, 'deviceId')}"
    end
  end
end
