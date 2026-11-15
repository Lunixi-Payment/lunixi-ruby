# frozen_string_literal: true

require_relative 'test_helper'

# Every required operation of the shared SDK catalog (contracts/products at the repository root) is a
# method of the Ruby client. Names that differ on purpose come from contracts/sdk-names.json. The
# catalog is not shipped with the published gem repository; the test is skipped there.
class ParityTest < Minitest::Test
  REPO = File.expand_path('../..', __dir__)
  PRODUCTS = %w[payments fraud payment-links reference physical-pos wallet bank-connect sanction insurance subscriptions kyc identity
                marketplace].freeze
  # Route tables kept field by field identical to the catalog's routes groups (method, path, key rule,
  # body and query lists, anyOf, binary, screening, stepUp, free, optionalBody, anyQuery).
  ROUTE_TABLES = {
    'wallet' => { 'WALLET_ROUTES' => Lunixi::WALLET_ROUTES },
    'bank-connect' => { 'BANK_TRANSFER_ROUTES' => Lunixi::BANK_TRANSFER_ROUTES },
    'sanction' => { 'SANCTION_ROUTES' => Lunixi::SANCTION_ROUTES },
    'subscriptions' => { 'SUBSCRIPTION_ROUTES' => Lunixi::SUBSCRIPTION_ROUTES },
    'kyc' => { 'KYC_ROUTES' => Lunixi::KYC_ROUTES },
    'identity' => { 'IDENTITY_ROUTES' => Lunixi::IDENTITY_ROUTES },
    'marketplace' => { 'MARKETPLACE_ROUTES' => Lunixi::MARKETPLACE_ROUTES }
  }.freeze
  # Catalog list groups and the Ruby list that must equal them.
  LIST_GROUPS = {
    'wallet' => { 'WALLET_AMOUNT_FIELDS' => Lunixi::WALLET_AMOUNT_FIELDS, 'WalletAccountType.ALL' => Lunixi::WalletAccountType::ALL,
                  'WalletBulkTargetType.ALL' => Lunixi::WalletBulkTargetType::ALL,
                  'WalletCorporateAccountStatus.ALL' => Lunixi::WalletCorporateAccountStatus::ALL,
                  'WalletEndUserStatus.ALL' => Lunixi::WalletEndUserStatus::ALL, 'WalletKycLevel.ALL' => Lunixi::WalletKycLevel::ALL,
                  'WalletOtpChannel.ALL' => Lunixi::WalletOtpChannel::ALL, 'WalletQrImageFormat.ALL' => Lunixi::WalletQrImageFormat::ALL,
                  'WalletQrType.ALL' => Lunixi::WalletQrType::ALL },
    'bank-connect' => Lunixi::BANK_CONNECT_FILTERS.to_h { |route, filters| ["BANK_CONNECT_FILTERS.#{route}", filters] }.merge(
      'BANK_CONNECT_EVENT_TYPES' => Lunixi::BankConnectEvents::ALL, 'BANK_TRANSFER_EVENT_TYPES' => Lunixi::BankTransferEvents::ALL,
      'BankAccountStatus.ALL' => Lunixi::BankAccountStatus::ALL, 'BankAvailability.ALL' => Lunixi::BankAvailability::ALL,
      'BankCapability.ALL' => Lunixi::BankCapability::ALL, 'BankConnectionStatus.ALL' => Lunixi::BankConnectionStatus::ALL,
      'BankFxOrderStatus.ALL' => Lunixi::BankFxOrderStatus::ALL, 'BankFxRequestedSide.ALL' => Lunixi::BankFxRequestedSide::ALL,
      'BankSyncStatus.ALL' => Lunixi::BankSyncStatus::ALL, 'BankTransactionDirection.ALL' => Lunixi::BankTransactionDirection::ALL,
      'BankTransactionType.ALL' => Lunixi::BankTransactionType::ALL, 'BankTransferInitiatedVia.ALL' => Lunixi::BankTransferInitiatedVia::ALL,
      'BankTransferRail.ALL' => Lunixi::BankTransferRail::ALL, 'BankTransferStatus.ALL' => Lunixi::BankTransferStatus::ALL
    ),
    'sanction' => Lunixi::SANCTION_VALUE_SETS.to_h { |field, values| ["SANCTION_VALUE_SETS.#{field}", values] }.merge(
      'CoverageStatus.ALL' => Lunixi::SanctionCoverageStatus::ALL, 'HitType.ALL' => Lunixi::SanctionHitType::ALL,
      'RiskDomain.ALL' => Lunixi::SanctionRiskDomain::ALL, 'ScreenMode.ALL' => Lunixi::SanctionScreenMode::ALL,
      'SubjectType.ALL' => Lunixi::SanctionSubjectType::ALL, 'WalletScreenMode.ALL' => Lunixi::SanctionWalletScreenMode::ALL
    ),
    'insurance' => Lunixi::INSURANCE_FILTERS.to_h { |route, filters| ["INSURANCE_FILTERS.#{route}", filters] }.merge(
      'INSURANCE_CONSENT_FIELDS' => Lunixi::INSURANCE_CONSENT_FIELDS, 'INSURANCE_EVENT_TYPES' => Lunixi::InsuranceEvents::ALL,
      'INSURANCE_EXTERNAL_PAYMENT_FIELDS' => Lunixi::INSURANCE_EXTERNAL_PAYMENT_FIELDS,
      'INSURANCE_EXTERNAL_REFUND_FIELDS' => Lunixi::INSURANCE_EXTERNAL_REFUND_FIELDS, 'INSURANCE_LEAD_FIELDS' => Lunixi::INSURANCE_LEAD_FIELDS,
      'INSURANCE_ORDER_FIELDS' => Lunixi::INSURANCE_ORDER_FIELDS, 'INSURANCE_PRODUCT_SEARCH_FIELDS' => Lunixi::INSURANCE_PRODUCT_SEARCH_FIELDS,
      'INSURANCE_QUOTE_FIELDS' => Lunixi::INSURANCE_QUOTE_FIELDS, 'InsuranceEvents.LEAD_EVENTS' => Lunixi::InsuranceEvents::LEAD_EVENTS,
      'InsuranceEvents.ORDER_EVENTS' => Lunixi::InsuranceEvents::ORDER_EVENTS,
      'InsuranceCollectionStatus.ALL' => Lunixi::InsuranceCollectionStatus::ALL,
      'InsuranceDocumentStatus.ALL' => Lunixi::InsuranceDocumentStatus::ALL, 'InsuranceLeadStatus.ALL' => Lunixi::InsuranceLeadStatus::ALL,
      'InsuranceOrderStatus.ALL' => Lunixi::InsuranceOrderStatus::ALL, 'InsuranceOrderSurface.ALL' => Lunixi::InsuranceOrderSurface::ALL,
      'InsurancePaymentMode.ALL' => Lunixi::InsurancePaymentMode::ALL, 'InsurancePolicyStatus.ALL' => Lunixi::InsurancePolicyStatus::ALL,
      'InsurancePremiumCollectedBy.ALL' => Lunixi::InsurancePremiumCollectedBy::ALL,
      'InsuranceQuoteStatus.ALL' => Lunixi::InsuranceQuoteStatus::ALL, 'InsuranceReferenceKind.ALL' => Lunixi::InsuranceReferenceKind::ALL,
      'InsuranceRefundStatus.ALL' => Lunixi::InsuranceRefundStatus::ALL
    ),
    'subscriptions' => { 'CollectionMethod.ALL' => Lunixi::SubscriptionCollectionMethod::ALL,
                         'SUBSCRIPTION_ACTIVE_STATES' => Lunixi::SUBSCRIPTION_ACTIVE_STATES,
                         'SUBSCRIPTION_BILLING_RULE_FIELDS' => Lunixi::SUBSCRIPTION_BILLING_RULE_FIELDS,
                         'SUBSCRIPTION_EVENT_TYPES' => Lunixi::SUBSCRIPTION_EVENT_TYPES,
                         'SUBSCRIPTION_TERMINAL_STATES' => Lunixi::SUBSCRIPTION_TERMINAL_STATES,
                         'SubscriptionStatus.ACTIVE_STATES' => Lunixi::SubscriptionStatus::ACTIVE_STATES,
                         'SubscriptionStatus.TERMINAL_STATES' => Lunixi::SubscriptionStatus::TERMINAL_STATES },
    'kyc' => { 'AchievedAssurance.DOMAINS' => Lunixi::KycAssuranceDomain::ALL, 'EvidencePurpose.ALL' => Lunixi::KycEvidencePurpose::ALL,
               'KYC_EVENT_TYPES' => Lunixi::KYC_EVENT_TYPES, 'KYC_SESSION_TERMINAL_STATES' => Lunixi::KYC_SESSION_TERMINAL_STATES,
               'SessionStatus.TERMINAL_STATES' => Lunixi::KycSessionStatus::TERMINAL_STATES, 'SessionType.ALL' => Lunixi::KycSessionType::ALL },
    'identity' => { 'IDENTITY_ANALYZE_FIELDS' => Lunixi::IDENTITY_ANALYZE_FIELDS },
    'marketplace' => { 'MARKETPLACE_CHARGE_REQUIRED_FIELDS' => Lunixi::MARKETPLACE_CHARGE_REQUIRED_FIELDS,
                       'MARKETPLACE_SELLER_FIELDS' => Lunixi::MARKETPLACE_SELLER_FIELDS }
  }.freeze
  # Catalog enum groups ({ "NAME": "value" }) and the Ruby module whose String constants must equal them.
  ENUM_GROUPS = {
    'subscriptions' => { 'BillingRule' => Lunixi::SubscriptionBillingFrequency, 'ChangePlanRequest' => Lunixi::SubscriptionPlanChangeBehavior,
                         'CollectionMethod' => Lunixi::SubscriptionCollectionMethod, 'InvoiceStatus' => Lunixi::SubscriptionInvoiceStatus,
                         'SubscriptionBillingFrequency' => Lunixi::SubscriptionBillingFrequency,
                         'SubscriptionCardVerificationMode' => Lunixi::SubscriptionCardVerificationMode,
                         'SubscriptionCollectionMethod' => Lunixi::SubscriptionCollectionMethod, 'SubscriptionEvents' => Lunixi::SubscriptionEvents,
                         'SubscriptionInvoiceStatus' => Lunixi::SubscriptionInvoiceStatus,
                         'SubscriptionPlanChangeBehavior' => Lunixi::SubscriptionPlanChangeBehavior,
                         'SubscriptionPortalSdkMode' => Lunixi::SubscriptionPortalSdkMode, 'SubscriptionStatus' => Lunixi::SubscriptionStatus },
    'kyc' => { 'AchievedAssurance' => Lunixi::KycAssuranceDomain, 'AssuranceLevel' => Lunixi::KycAssuranceLevel,
               'EvidencePurpose' => Lunixi::KycEvidencePurpose, 'KycAssuranceDomain' => Lunixi::KycAssuranceDomain,
               'KycAssuranceLevel' => Lunixi::KycAssuranceLevel, 'KycEvents' => Lunixi::KycEvents, 'KycEvidencePurpose' => Lunixi::KycEvidencePurpose,
               'KycSessionStatus' => Lunixi::KycSessionStatus, 'KycSessionType' => Lunixi::KycSessionType, 'SessionStatus' => Lunixi::KycSessionStatus,
               'SessionType' => Lunixi::KycSessionType },
    'marketplace' => { 'DealerStatus' => Lunixi::MarketplaceDealerStatus, 'MarketplaceDealerStatus' => Lunixi::MarketplaceDealerStatus,
                       'MarketplaceDealerType' => Lunixi::MarketplaceDealerType,
                       'MarketplaceMultiSellerPolicy' => Lunixi::MarketplaceMultiSellerPolicy }
  }.freeze
  # Catalog single-value groups and the Ruby constant that must equal their one value.
  VALUE_GROUPS = {
    'subscriptions' => { 'PortalLink' => Lunixi::SUBSCRIPTION_PORTAL_HOSTED_BASE },
    'marketplace' => { 'DealerOnboardingLink' => Lunixi::MARKETPLACE_DEALER_ONBOARDING_HOSTED_BASE }
  }.freeze
  # Catalog pattern groups ({ "$pattern": "^…$" }) and the Ruby regexp (\A…\z) that must equal them.
  PATTERN_GROUPS = {
    'bank-connect' => { 'BANK_TRANSFER_IDEMPOTENCY_KEY_PATTERN' => Lunixi::BANK_TRANSFER_IDEMPOTENCY_KEY_PATTERN,
                        'BANK_TRANSFER_PAYMENT_PURPOSE_PATTERN' => Lunixi::BANK_TRANSFER_PAYMENT_PURPOSE_PATTERN },
    'insurance' => { 'INSURANCE_IDEMPOTENCY_KEY_PATTERN' => Lunixi::INSURANCE_IDEMPOTENCY_KEY_PATTERN }
  }.freeze

  def setup
    @sdk = client(transport: RecordingTransport.new { response })
  end

  def test_required_catalog_operations_are_client_methods
    catalogs = PRODUCTS.map { |product| File.join(REPO, 'contracts', 'products', "#{product}.json") }.select { |path| File.file?(path) }
    skip 'contracts/products is not part of this checkout' if catalogs.empty?

    names = ruby_names
    required = catalogs.flat_map do |path|
      JSON.parse(File.read(path, encoding: 'UTF-8')).fetch('operations').select { |_, meta| meta['status'] == 'required' }.keys
    end
    refute_empty required
    missing = required.reject { |operation| implemented?(operation, names) }
    assert_empty missing, "Required catalog operations missing from the Ruby client: #{missing.join(', ')}"
  end

  def test_route_tables_match_the_catalog
    compared = 0
    ROUTE_TABLES.each do |product, tables|
      groups = catalog_groups(product) or next
      tables.each do |group, table|
        expected = groups.fetch(group).fetch('values')
        assert_equal expected.keys.sort, table.keys.sort, "#{group} route names"
        expected.each { |name, route| assert_equal route, table.fetch(name), "#{group}.#{name}" }
        compared += 1
      end
    end
    skip 'contracts/products is not part of this checkout' if compared.zero?
  end

  def test_value_and_field_lists_match_the_catalog
    compared = 0
    LIST_GROUPS.each do |product, lists|
      groups = catalog_groups(product) or next
      lists.each do |group, list|
        assert_equal groups.fetch(group).fetch('values'), list, "#{product} #{group}"
        compared += 1
      end
    end
    skip 'contracts/products is not part of this checkout' if compared.zero?
  end

  def test_enum_groups_match_the_catalog
    compared = 0
    ENUM_GROUPS.each do |product, enums|
      groups = catalog_groups(product) or next
      enums.each do |group, mod|
        constants = mod.constants.to_h { |name| [name.to_s, mod.const_get(name)] }.select { |_, value| value.is_a?(String) }
        assert_equal groups.fetch(group).fetch('values'), constants, "#{product} #{group}"
        compared += 1
      end
    end
    VALUE_GROUPS.each do |product, values|
      groups = catalog_groups(product) or next
      values.each do |group, value|
        assert_equal [value], groups.fetch(group).fetch('values').values, "#{product} #{group}"
        compared += 1
      end
    end
    skip 'contracts/products is not part of this checkout' if compared.zero?
  end

  def test_patterns_match_the_catalog
    compared = 0
    PATTERN_GROUPS.each do |product, patterns|
      groups = catalog_groups(product) or next
      patterns.each do |group, regexp|
        expected = groups.fetch(group).fetch('values').fetch('$pattern').sub(/\A\^/) { '\A' }.sub(/\$\z/) { '\z' }
        assert_equal expected, regexp.source, "#{product} #{group}"
        compared += 1
      end
    end
    skip 'contracts/products is not part of this checkout' if compared.zero?
  end

  private

  def catalog_groups(product)
    path = File.join(REPO, 'contracts', 'products', "#{product}.json")
    File.file?(path) ? JSON.parse(File.read(path, encoding: 'UTF-8')).fetch('groups') : nil
  end

  def ruby_names
    path = File.join(REPO, 'contracts', 'sdk-names.json')
    File.file?(path) ? JSON.parse(File.read(path, encoding: 'UTF-8')).fetch('ruby', {}) : {}
  end

  # accessor.sub.method resolves through the client's accessors; a renamed operation may be defined on
  # the sub-client or on one of its parents (e.g. fraud.record_event for fraud.events.record).
  def implemented?(operation, names)
    return true if names.key?(operation) && names[operation].nil?

    *accessors, leaf = operation.split('.')
    chain = [@sdk]
    accessors.each do |accessor|
      name = snake(accessor)
      return false unless sdk_method?(chain.last, name)

      chain << chain.last.public_send(name)
    end
    return sdk_method?(chain.last, snake(leaf)) unless names.key?(operation)

    chain.drop(1).reverse.any? { |target| sdk_method?(target, names.fetch(operation)) }
  end

  # Defined by the SDK, not inherited from Object or Kernel (Object#send must not count as send).
  def sdk_method?(target, name)
    target.respond_to?(name) && target.method(name).owner.name.to_s.start_with?('Lunixi::')
  end

  # The catalog rule: "_" between a lowercase and an uppercase letter, and before an uppercase +
  # lowercase pair that follows an uppercase letter or a digit (quoteW2W -> quote_w2w, completeW2Iban ->
  # complete_w2_iban).
  def snake(name)
    name.gsub(/([a-z])([A-Z])/, '\1_\2').gsub(/([A-Z0-9])([A-Z][a-z])/, '\1_\2').downcase
  end
end
