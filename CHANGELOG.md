# Changelog

## 2.0.0 — 2026-11-20

- **Breaking — order details required.** Every payment endpoint requires the buyer, the billing address and at least one basket item; a `PHYSICAL` item also requires the shipping address (payment providers do not start a payment without them). `payments.create_intent`, `payments.create_marketplace_intent`, `payments.direct_method_payment`, `payments.split`, `marketplace.create_checkout_intent`, the marketplace card charges and `payments.store_card` (buyer and billing address only) raise `ConfigurationError` naming the missing paths before sending; on the checkout intents `buyer.ip` may be left out (the Lunixi form takes it from the browser). `StoreCardRequest` gains `with_buyer` / `with_billing_address`. New `Lunixi::OrderDetails.missing(body, basket:, checkout_intent:)` / `OrderDetails.check!` and constants `ORDER_DETAILS_REQUIRED_FIELDS`, `BUYER_REQUIRED_FIELDS`, `CHECKOUT_INTENT_BUYER_OPTIONAL_FIELDS`, `ADDRESS_REQUIRED_FIELDS`, `BASKET_ITEM_REQUIRED_FIELDS`, `OrderFieldErrorCode` (`payment.order.field_required`, `payment.order.field_invalid`), `OrderFieldReason`.
- Split payment bodies carry `buyer`, `billingAddress`, `shippingAddress` and `basketItems`; their field list is `Lunixi::SPLIT_PAYMENT_FIELDS`.
- Wallet card top-up (`wallet.topups.start_card`): `buyer` and `billingAddress` are required, `shippingAddress` optional; a missing field raises `ConfigurationError` before sending (the gateway answers 400 `payment.order.field_required` with `details.fields`).
- **Breaking — subscription customers.** `subscriptions.customers.upsert` requires `name`, `surname`, `email`, `gsmNumber`, `identityNumber`, `billingAddress`, `billingCity`, `billingCountry`, `billingZipCode` (renewals take the buyer from this record); `phone`, `locale` and `metadata` were never accepted by the gateway and are removed from the route. New constant `Lunixi::SubscriptionCustomerErrorCode`.
- **Breaking — payment link buyer fields.** `Lunixi::BuyerFieldRequirement` has only `REQUIRED`: the link page always asks all five buyer fields (the gateway answers `HIDDEN` / `OPTIONAL` with 400).
- Rails sample: `Order.order_details` (encrypted, migration `20261120000000_add_order_details_to_orders`) carries the buyer, addresses and basket; checkout checks them before reserving an attempt and sends them with the intent outside the reserved request.

## 1.3.1 — 2026-11-15

- Lint (RuboCop) clean and `Gemfile.lock` carries the gem version, so the release builds in CI; no behaviour change.

## 1.3.0 — 2026-11-15

- `payments.direct_method_payment(body_or_request, idempotency_key:)` and `Lunixi::DirectMethodPaymentRequest`: start a payment with any method (`POST /payments/direct/payment`, signed). Raw and built bodies are checked before sending: known fields, only the chosen method's block, card fields only with `CARD`, block structure, promissory-note plan, 1–100 basket items for `SHOPPING_LOAN`, no `providerCode` for `BANK_TRANSFER`; the idempotency key is required.
- `payments.confirm_payment_action` / `payments.resend_payment_action` for OTP, consent and input actions; the confirm body carries only `otp`, `consentAccepted` and `fields`.
- `payments.list_payment_methods` alias of `payments.methods`; the `payment_method:` code is checked locally and `QR` is sent as `QR_CODE`.
- Promissory notes: `payments.get_promissory_notes`, `payments.cancel_promissory_notes`, `payments.download_promissory_note_document` (PDF bytes) and the plan rules (schedule or note count, at most 24 notes).
- Bank transfer: `payments.list_bank_transfer_exceptions`, `payments.accept_bank_transfer_exception`, `payments.mark_bank_transfer_exception_refunded` and `Lunixi::BankTransferInstruction.from_response` for the `DISPLAY` transfer instruction.
- `payments.list_splits(**filters)`; split legs other than card carry only `mobileBilling`, `wallet` or `promissoryNote`.
- `client.reference` address dictionary: `list_provinces`, `list_districts`, `list_neighborhoods`.
- Constants: `Lunixi::PaymentMethod`, `PaymentActionType`, `ProviderSelection`, `ProviderSelectionMode`, field lists (`METHOD_BLOCK_FIELDS`, `DIRECT_METHOD_PAYMENT_FIELDS`, `CARD_ONLY_FIELDS`, `PAYMENT_ACTION_CONFIRM_FIELDS`, `SPLIT_LEG_BLOCK_FIELDS`, `SPLIT_PAYMENT_LEG_FIELDS`, `LIST_SPLIT_PAYMENTS_FILTERS`), bank transfer, promissory-note and split values and webhook event names.
- `Client#request` takes `accept:` for endpoints that answer with another media type; the default stays `application/json`.
- `payments.bin_info`, `payments.installment_options` (with `Lunixi::InstallmentOptionsRequest`) and `payments.card_taxonomy`. Card numbers and BINs never appear in error messages or builder `inspect` output.
- Stored cards: `payments.store_card` (with `Lunixi::StoreCardRequest`), `payments.list_stored_cards`, `payments.get_stored_card` and `payments.deactivate_stored_card`; both writes are signed and require the idempotency key.
- `payments.create_marketplace_intent(body, idempotency_key:)` (signed): `sellers[].amountMinor` must be canonical minor-unit strings adding up to `amount`, checked before sending.
- `payments.failover_recovery_analytics(**filters)` and `payments.provider_credential_analytics(credential_id, **filters)`.
- `enabledInstallments` of `create_intent`, `create_marketplace_intent` and `installment_options` is checked before sending (distinct integers 1–36 that include 1) and sent in ascending order; a list the gateway would reject with 400 now raises `ConfigurationError`.
- `client.payment_links`: `create`, `list`, `get`, `update`, `pause`, `resume`, `deactivate`, `action`, `send_link`, `qr` (image bytes), `list_attempts`, `list_payments`, and the image upload `create_image_upload`, `confirm_image_upload` and `upload_image`. Every gateway call is signed; the presigned image PUT goes to the storage host with only `uploadHeaders`, never with the access token or the signature. Value sets `Lunixi::PaymentLinkUsage`, `PaymentLinkAmountMode`, `PaymentLinkState`, `PaymentLinkAttemptState`, `PaymentLinkEnvironment`, `BuyerFieldRequirement`, `CustomFieldType`, `PaymentLinkButtonLabel`, `PaymentLinkDeliveryChannel`, `PaymentLinkQrFormat`, `PaymentLinkLocale`, `PaymentLinkImageContentType` and the field lists `PAYMENT_LINK_SPEC_FIELDS`, `PAYMENT_LINK_IMMUTABLE_FIELDS`.
- Fraud decision log: `fraud.decisions.list`, `fraud.decisions.get` and `fraud.decisions.latest_for_payment`. Fraud events: `fraud.events.record` (`fraud.record_event` stays and calls it) and `fraud.events.record_batch` (signed, at most 500 events).
- A parity test checks every required operation of the shared SDK catalog against the client when the catalog is present.
- `client.physical_pos` (card terminals, `/api/v1/physical-pos`): `create_payment` (`SALE`, `PREAUTH_OPEN`, `REFUND_UNMATCHED`; target by `deviceId`, `vendorCode` + `serialNumber` or `externalRef`; sale items with `taxGroupCode`; `interaction` and `terminalProviderId` for provider-collected cards), `create_reversal` (`VOID`, `REFUND` by amount or items, `PREAUTH_CLOSE`, `PREAUTH_CANCEL`), `cancel_payment`, `get_payment`, `list_payments`, `list_transactions`, `get_transaction`, `list_ambiguous_payments`, `get_sales_summary`, `get_tax_summary`, `list_settlements`, `start_settlement`, `list_settlement_runs`, `get_settlement_run` and `iterate_*` for every list. Payment writes return `Lunixi::PhysicalPosWriteResult` (`payment`, `replayed`, `status_code` 202 new / 200 replay, `idempotency_key`); `create_payment` and `create_reversal` require the idempotency key and send it exactly as given; an uncertain outcome (no answer, a 5xx that does not say "not started", a 2xx without a payment) is retried with the same key and body and then raises `Lunixi::PhysicalPosOutcomeUnknownError`.
- `client.physical_pos_management`: overview, catalog (vendors, device models, acquirers), stores, registers, logical terminals with their bank rows, payment-provider rows and device links, devices (assignment, lifecycle, retirement), device identity keys (revocation, enrollment revert, activation-code revocation), end-of-day policies for the account, a store or a device and the effective policy, audit and history lists. Updates take the `rowVersion` you last read; keyed writes generate a UUID when the key is `nil`.
- Physical POS request checks before sending: closed field and filter lists (`Lunixi::PHYSICAL_POS_REQUEST_FIELDS`, `Lunixi::PHYSICAL_POS_FILTERS`), canonical minor-unit money strings, and card data (a PAN, track, expiry or security-code field at any depth, or a card number in `merchantReference`, an item name, a tax group or a free-text filter) raises `Lunixi::PhysicalPosCardDataRejectedError` with the field path only.
- Physical POS errors: `PhysicalPosCardDataRejectedError` (`field`), `PhysicalPosVoidAfterSettlementError` (`allowed_operation`), `PhysicalPosRateLimitError` (`retry_after` in seconds) and `PhysicalPosOutcomeUnknownError` (`attempts`); the key of a write is on the error as `idempotency_key`. `ApiError#details` keeps only the safe `field`, `allowedOperation` and `retryAfterSeconds` values of a gateway answer.
- `Lunixi::PhysicalPosWebhook.parse` (also `Lunixi::PhysicalPos.parse_webhook_event`): verifies the signature first, then reads a `physical_pos.*` event with `category`, `history_seq`, `original`, the optional `cashier` and `device_sale?`, and checks its amounts. Values: `Lunixi::PhysicalPosEvents`, `PhysicalPosPaymentOperation`, `PhysicalPosPaymentStatus`, `PhysicalPosReversalStatus`.
- `Client#request` takes `max_retries:` to lower the retry budget of one call.
- `client.wallet` (`/api/v1/wallet`): `ping` and the sub-clients `programs`, `end_users`, `wallets`, `deposits`, `corporate`, `fees`, `transfers` (`quote_w2w`, `initiate_w2w`, `complete_w2w`, `quote_w2_iban`, `initiate_w2_iban`, `complete_w2_iban`), `withdrawals`, `operations`, `topups`, `payments`, `qr` (`image` returns bytes) and `bulk_payouts`, with `iterate` on the cursor lists. Every call is signed and checked against `Lunixi::WALLET_ROUTES` before sending: unknown or missing fields, nested rows and bulk items, non-canonical amounts (numbers, decimals) and a missing or malformed `Idempotency-Key` (1–128 characters) raise `ConfigurationError`. The complete calls put `operationId` in the body themselves. `end_users.freeze_end_user(end_user_id, ...)` freezes an end user (named so that `Object#freeze` keeps its meaning).
- `client.bank_connect` (`/api/v1/bank-connect`): `list_banks`, `list_connections`, `get_connection`, `list_accounts`, `get_account`, `request_sync`, `list_balances`, `list_transactions`, `get_transaction` and `iterate_*`. Filters are checked against `Lunixi::BANK_CONNECT_FILTERS` before sending (value sets, `limit` 1–100, at most 100 account ids, canonical amount strings, `minAmountMinor` not above `maxAmountMinor`, `bookedTo` only with `bookedFrom`, at most 92 days).
- `bank_connect.transfers` (`list_purposes`, `create`, `list`, `iterate`, `get`) and `bank_connect.fx` (`list_rates`, `create_quote`, `create_order`, `list_orders`, `iterate_orders`, `get_order`) through `Lunixi::BANK_TRANSFER_ROUTES`. `create` and `create_order` check a given `Idempotency-Key` (8–200 printable ASCII) or generate a UUID v4, and retry a network error or a 5xx with the same key and body; an answered error carries the key as `idempotency_key`. Bodies are checked before sending (fields, positive amount strings, receiver name and IBAN length, purpose code, description length, exactly one quote amount, two different accounts).
- `client.sanction` (`/api/v1/sanction`, access token only): `screen_name`, `screen_wallet`, `screen_account`, `screen_transaction`, `screen_public_procurement_ban`, `screen_adverse_media`, `evaluate_behavioral_alert`, `list_screening_history`, `register_monitoring` (a `profile` Hash is sent as `profileJson`), `list_monitoring_alerts`, `list_monitored_entities`, `list_monitoring_matches`, `get_dataset_freshness`, `search_entities`, `get_entity_profile`, `get_entity_graph`, `get_indirect_exposure`, `get_ownership_aggregation`, `list_blacklist_entries` and `iterate_*`. Bodies and filters are checked against `Lunixi::SANCTION_ROUTES`, `SANCTION_NESTED_FIELDS` and `SANCTION_VALUE_SETS`; a screening answer whose `status` is not `success` raises `ApiError`. `Lunixi::Sanction.clear_screening?(result)` applies the clean-read rule (no match or hit, no blocking flag or decision, `coverageStatus` `COMPLETE` when reported).
- `client.insurance` (`/api/v1/insurance`, I1–I22): `list_products`, `search_products`, `list_reference_values`, `create_quote`, `get_quote`, `create_order`, `list_orders`, `get_order`, `bind_payment`, `confirm_payment`, `issue_policy`, `cancel_order`, `refund_premium`, `get_policy_document`, `get_policy_receipt`, `get_policy_certificate` (PDF bytes), `get_reconciliation_summary`, `list_reconciliation_orders`, `export_reconciliation` (`Lunixi::InsuranceReconciliationExport` with the CSV bytes, `truncated?`, `next_cursor`, `aborted?`), `create_lead`, `list_leads`, `get_lead`, `iterate_*`, and the helpers `Lunixi::Insurance.consent_from_quote` and `Lunixi::Insurance.premium_basket_item`. Every call is signed; `create_order`, `confirm_payment`, `issue_policy`, `cancel_order`, `refund_premium` and `create_lead` require the `Idempotency-Key` (8–200 printable ASCII), `create_quote` and `bind_payment` take it optionally. A quote with both `paymentIntentId` and `context.items` raises `ConfigurationError`; the fields of an insurance type's own object are left to the gateway.
- Webhook readers that verify the signature first: `Lunixi::BankConnectWebhook` (`bank_account.transaction.received`), `Lunixi::BankTransferWebhook` (Bank Connect `bank_transfer.*`, not the payment method's `payment.bank_transfer.*`) and `Lunixi::InsuranceWebhook` (order events and `insurance.lead.submitted`), each with `parse(raw_body, headers, secret_or_verifier)` and `from_event(verified_event)`; `data` holds the documented fields only and its amounts are checked. Event names: `Lunixi::BankConnectEvents`, `BankTransferEvents`, `InsuranceEvents`.
- Value sets for the four products (`WalletKycLevel`, `BankTransferStatus`, `SanctionRiskDomain`, `InsuranceOrderStatus` …) and `Lunixi::ListPage` (`items`, `next_cursor`, `has_more?`, `total_count`, `raw`) for their lists.
- The bank-connect balance fields (`availableMinor`, `blockedMinor`, `balanceAfterMinor`, `sourceBalanceAfterMinor`, `targetBalanceAfterMinor` …) and the `options` / `quote` containers are part of the canonical money check.
- The parity test also compares the wallet, bank transfer and sanction route tables, the filter, field and value lists and the key patterns with the shared catalog.
- `client.subscriptions` (`/api/v1/subscriptions`, access token only): `create` (the `Idempotency-Key` is required and also sent in the body), `get`, `list`, `iterate`, `cancel(at_period_end:)`, `pause(resume_at:)`, `resume`, `change_plan`, `audit_logs`, and the sub-clients `plans` (`create` checks the price, currency and billing rule), `customers`, `cards` (a `paymentMethodToken`, never a card number), `invoices`, `portal` (SDK session, hosted links on `/api/panel/v1/subscriptions/portal`, invite, settings), `products`, `features`, `addons` and `usage`. Checked against `Lunixi::SUBSCRIPTION_ROUTES`; money members of bodies, filters and answers must be canonical minor-unit strings. Helpers `Lunixi::Subscriptions.active?`, `terminal?` and `portal_url`; values `SubscriptionStatus`, `SubscriptionInvoiceStatus`, `SubscriptionCollectionMethod`, `SubscriptionBillingFrequency`, `SubscriptionCardVerificationMode`, `SubscriptionPlanChangeBehavior`, `SubscriptionPortalSdkMode`, `SubscriptionEvents`.
- `client.kyc` (`/api/v1/kyc`, access token only): `create_session`, `get_session`, `list_sessions` (only `limit` / `cursor`), `iterate_sessions`, `set_jurisdiction`, `set_primary_document`, `upload_document`, `timeline`, `submit`, `manual_review`, `evidence_request`, `merchant_policy`, `update_merchant_policy`, `rotate_webhook_secret`, `webhook_outbox`, `retry_webhook_event`, `erasure_requests`. `person:` / `company:` become `customer`, `metadata:` becomes `evidenceContextJson`. Helpers `Lunixi::Kyc.session_terminal?`, `assurance_rank`, `assurance_meets?`; values `KycSessionType`, `KycSessionStatus`, `KycEvidencePurpose`, `KycAssuranceLevel`, `KycAssuranceDomain`, `KycEvents`.
- `client.identity` (`/api/v1/identity/live-sessions`, access token only): `analyze_sync`, `analyze`, `account_links`, `get_session`, `related_sessions`, `timeline`, `top_sources`, `list_sessions`; helpers `Lunixi::Identity.device_shared?` and `link_reasons`.
- `client.marketplace`: the signed split charges `create_checkout_intent`, `charge_marketplace_card`, `charge_marketplace_card2d`, `charge_marketplace_card3d` (seller legs as arguments, adding up to `amount`; an intent without a token or form raises `ApiError`; card data never reaches an error message), and the sub-dealer, commission, payout and audit-log routes. Helper `Lunixi::Marketplace.onboarding_url`; values `MarketplaceDealerStatus`, `MarketplaceDealerType`, `MarketplaceMultiSellerPolicy`.
- `Lunixi::ListPage#page_size` (the page size of a subscription list); `Client#request` accepts the subscription portal panel routes (`/api/panel/v1/subscriptions/portal/...`).
- The parity test covers the subscription, KYC, identity and marketplace operations, route tables, lists and enum values.

## 1.2.2 — 2026-11-12

- Development lockfile only: Rails sample dependencies moved to patched versions (rails 8.1.4.1, nokogiri 1.19.7, loofah 2.25.3, rails-html-sanitizer 1.7.2) for new security advisories. The gem itself and its runtime dependencies are unchanged.

## 1.2.1 — 2026-11-12

- Packaging-only release of 1.2.0 (RuboCop: no trailing comma in `ProductCategory::ALL`). No API change.

## 1.2.0 — 2026-11-12

- Document the optional `basketItems[].productCategory` field of the `create_intent` body: the Lunixi product category code, used by payment methods with legal installment limits (e.g. shopping loan) and other platform features. The body is sent unchanged; leaving it out keeps today's behaviour, and the gateway answers an unknown code with 400.
- `Lunixi::ProductCategory`: the 40 product category codes as frozen string constants (e.g. `Lunixi::ProductCategory::MOBILE_PHONE`) and the frozen `Lunixi::ProductCategory::ALL` in dictionary order. The list only grows by appending; values are not checked against it before sending.

## 1.1.0 — 2026-11-04

- Document the optional `enabledInstallments` field of the `create_intent` body: the installment counts the hosted form may offer for one payment (`[1]` = single payment only). It only narrows the panel settings, the card and the platform maximum; leaving it out means no restriction. The body is sent unchanged; send distinct integers 1–36 that include 1, in ascending order (the gateway answers any other list with 400).

## 1.0.1 — 2026-11-01

- Align Rails sample API mocks and expectations with canonical minor-unit strings while preserving numeric-input rejection tests; runtime admission is unchanged.
- Preserve response parsing limits and error handling in a private helper; close RuboCop findings without suppressions.
- Update 1.0.1 installation and exact-tag publishing guidance.

## 1.0.0 — 2026-11-01

- Reject explicit null capture/refund amounts; full remaining operations use omission or the dedicated API described in MIGRATION-1.0.md.

- Breaking: public money request/response fields require canonical minor-unit strings; JSON numbers are rejected.
- Exact signed 64-bit fiat arithmetic and currency-aware decimal text conversion preserve values above JavaScript’s safe-integer limit.
- See [MIGRATION-1.0.md](MIGRATION-1.0.md) before upgrading.


## 0.1.2 — 2026-10-31

- Add strict backend payment-page URL and official embedded-form configuration helpers, without rebuilding hosted URLs from tokens.
- Default the Rails example to an on-site CDN-mounted form with escaped JSON, nonce CSP and optional explicit hosted mode.
- Freeze and encrypt request/mode before network dispatch, cache encrypted backend URLs, retain original uncertain keys/bodies and fence replay at 23 hours.
- Add an explicit migration preserving pre-existing orders as legacy hosted attempts; unknown legacy requests or missing URLs require reconciliation rather than a new charge.
- Preserve nonce CSP while allowing exact operator-approved HTTPS form-action origins for provider/legacy POSTs; reject unsafe origin configuration before use.


## 0.1.1 — 2026-10-31

- Add a bounded stateless Rails POST return adapter before parameter/session processing. It ignores gateway browser fields and redirects to the existing authenticated GET; checkout CSRF remains required.
- Add cross-site, empty-body, oversize and session-resume integration regressions. Browser returns never mark an order paid.

## 0.1.0 — 2026-10-31

- Initial server-side Ruby SDK: OpenSSL Ed25519 signing, JavaScript-compatible compact JSON, concurrent token cache and bounded HTTPS transport.
- Payment intent/status/list/methods/capture/refund/void/split helpers and fraud decision/event helpers.
- Caller-owned persistent idempotency keys, safe same-key retries, safe typed errors and redirect/path injection protection.
- Raw-body v2 webhooks with timestamp validation, rotation, constant-time comparison and a transactional replay-store contract.
- Executable Rails 8.1 reference integration with encrypted checkout tokens, CSRF, EN/TR UI and atomic database webhook handling.
- Offline cryptographic, transport/TLS and Rails integration tests; lint, dependency audit, Rails security scanning and CI.
- English and Turkish SDK/Rails guides. Source distribution; RubyGems publication is a separate release step.
