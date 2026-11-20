<p align="center"><img src=".github/assets/lunixi-logo.svg" width="300" alt="Lunixi"></p>

# Lunixi Ruby SDK

**Version 1.0.1 uses canonical minor-unit strings for money.** This is a breaking change from 0.x; update request and response handling together. See [migration](MIGRATION-1.0.md).

[English](README.md) · [Türkçe](README.tr.md) · [Documentation](https://docs.lunixi.com/sdks/ruby) · [Rails sample](samples/rails)

Server-side Ruby client for Lunixi payments, fraud and signed gateway requests. It signs requests with OpenSSL Ed25519, caches tokens across threads, preserves canonical minor-unit strings, retries safe operations with the same idempotency key, and verifies raw-body v2 webhooks. Private keys and card details stay out of the browser and application logs.

## Requirements and installation

Ruby **3.3+**, OpenSSL with **Ed25519** support, and Bundler. The runnable Rails sample uses **Rails 8.1** and SQLite. The core gem does not depend on Rails.

Add the published [1.0.1 dependency from RubyGems](https://rubygems.org/gems/lunixi-sdk/versions/1.0.1) and run `bundle install`:

```ruby
source 'https://rubygems.org'
gem 'lunixi-sdk', '1.0.1'
```

Keep `Gemfile.lock` to retain the reviewed dependency resolution.

Inside this checkout, `bundle exec ruby …` loads the local gem. An application can use a reviewed checkout with `gem 'lunixi-sdk', path: '/absolute/path/to/lunixi-ruby'`. Pin an audited commit when using a Bundler Git source. Never use an unpinned moving branch for a production deployment.

## Create a client

```ruby
require 'lunixi'

lunixi = Lunixi::Client.new(
  base_url: ENV.fetch('LUNIXI_BASE_URL'), # https://api-gateway.lunixi.com
  key_id: ENV.fetch('LUNIXI_KEY_ID'),
  private_key: File.read(ENV.fetch('LUNIXI_PRIVATE_KEY_PATH')),
  timeout: 30,
  max_retries: 2
)
```

Create one client per merchant connection and reuse it across requests. The key determines TEST/LIVE behavior; there is no fake local sandbox switch. Keep the private key outside the public web root and source control. Register its public key in the Lunixi dashboard. Accepted private-key encodings are Ed25519 PKCS#8 PEM, base64 PKCS#8 DER, or a base64 32-byte seed / 64-byte secret key. OpenSSL performs all curve operations.

Generate a new key pair securely on your own server:

```bash
umask 077
openssl genpkey -algorithm ED25519 -out lunixi-private.pem
openssl pkey -in lunixi-private.pem -pubout -out lunixi-public.pem
```

Only register `lunixi-public.pem` in the dashboard. Keep the private key in your secret store; the SDK never prints it.

## Start checkout

Calculate the total on the server and persist a UUID idempotency key with the payment attempt **before** calling Lunixi. Reuse that key after a timeout or process restart; create a different key only for a genuinely new operation.

```ruby
result = lunixi.payments.create_intent(
  {
    amount: "10050", # 100.50 TRY; integer kuruş, never 100.50
    currency: 'TRY',
    orderId: order.public_id,
    callbackUrl: 'https://merchant.example/payments/return',
    # Order details every payment requires (take them from your checkout, never a placeholder).
    # buyer.ip may be left out on an intent: the Lunixi form takes it from the buyer's browser.
    buyer: { name: 'Ada', surname: 'Yilmaz', identityNumber: '11111111111', email: 'ada@example.com',
             gsmNumber: '+905350000000', city: 'Istanbul', country: 'Turkey', zipCode: '34000' },
    billingAddress: { contactName: 'Ada Yilmaz', address: 'Example Street 1', city: 'Istanbul', country: 'Turkey', zipCode: '34000' },
    shippingAddress: { contactName: 'Ada Yilmaz', address: 'Example Street 1', city: 'Istanbul', country: 'Turkey', zipCode: '34000' },
    basketItems: [{ id: 'item-1', name: 'Product', category1: 'Electronics', itemType: 'PHYSICAL', price: "10050" }],
    enabledInstallments: [1, 2, 3] # optional: at most 3 installments
  },
  idempotency_key: order.persisted_payment_attempt_key
)

intent_id = result.fetch('data').fetch('paymentId')
checkout_token = result.fetch('data').fetch('token')
# Persist the intent id and encrypt the checkout token at rest.
# Optional hosted checkout uses the validated backend paymentPageUrl, never a URL built from this token.
```

Response envelopes are retained as received. An HTTP 2xx response, an intent/token, a return URL or an intermediate split state **does not mean funds were captured**. Confirm a verified payment webhook and reconcile the persisted intent, order reference, currency, amount and final status before fulfillment.

The shared Lunixi form owns enabled payment methods and supports the methods configured for the merchant, including eligible alternative methods and multi-card flows. Availability remains merchant/account dependent. Do not collect PAN/CVV through this SDK. The Rails example demonstrates fixed-total single-intent checkout; adapt accounting and final settlement checks before enabling split settlement, customer-paid insurance or surcharges in that example.

## API coverage

| Operation | Ruby API |
| --- | --- |
| Create intent | `payments.create_intent(body, idempotency_key:)` |
| Get/list payment | `payments.get(id)`, `payments.list(**filters)` |
| Enabled methods | `payments.methods(payment_method: nil)`, alias `payments.list_payment_methods(payment_method: nil)` |
| Pay with any method | `payments.direct_method_payment(body_or_request, idempotency_key:)`, `Lunixi::DirectMethodPaymentRequest` |
| Payment action | `payments.confirm_payment_action(payment_id, action_id, input)`, `payments.resend_payment_action(payment_id, action_id)` |
| Promissory notes | `payments.get_promissory_notes(id)`, `payments.cancel_promissory_notes(id, serial_numbers: nil, idempotency_key: nil)`, `payments.download_promissory_note_document(id, locale: nil)` |
| Bank transfer exceptions | `payments.list_bank_transfer_exceptions(environment: nil, status: nil, limit: nil)`, `payments.accept_bank_transfer_exception(id)`, `payments.mark_bank_transfer_exception_refunded(id)` |
| Address dictionary | `reference.list_provinces`, `reference.list_districts(province_code)`, `reference.list_neighborhoods(district_code)` |
| Capture/preauthorization | `payments.capture(id, idempotency_key:)` |
| Full/partial refund | `payments.refund(id, idempotency_key:, reason: nil)` |
| Void authorization | `payments.void(id, idempotency_key:)` |
| Split payment (1–5 legs) | `payments.split(body, idempotency_key:)` |
| Split status/list/refund | `payments.get_split(id)`, `payments.list_splits(**filters)`, `payments.refund_split(id, amount:, idempotency_key:, reason: nil)` |
| Marketplace intent | `payments.create_marketplace_intent(body, idempotency_key:)` |
| BIN and installments | `payments.bin_info(bin_or_pan)`, `payments.installment_options(body_or_request)`, `payments.card_taxonomy`, `Lunixi::InstallmentOptionsRequest` |
| Stored cards | `payments.store_card(body_or_request, idempotency_key:)`, `payments.list_stored_cards(card_user_key)`, `payments.get_stored_card(token)`, `payments.deactivate_stored_card(token, idempotency_key:)`, `Lunixi::StoreCardRequest` |
| Payment analytics | `payments.failover_recovery_analytics(**filters)`, `payments.provider_credential_analytics(credential_id, **filters)` |
| Payment links | `payment_links.create`, `list`, `get`, `update`, `pause`, `resume`, `deactivate`, `action`, `send_link`, `qr`, `list_attempts`, `list_payments` |
| Payment link image | `payment_links.create_image_upload`, `payment_links.confirm_image_upload(asset_id)`, `payment_links.upload_image(file_name:, content_type:, content:)` |
| Fraud decision | `fraud.evaluate(body)` |
| Fraud decision log | `fraud.decisions.list(**filters)`, `fraud.decisions.get(trace_id)`, `fraud.decisions.latest_for_payment(payment_id)` |
| Fraud transaction event | `fraud.record_event(body, idempotency_key:)` (same as `fraud.events.record`), `fraud.events.record_batch(events, idempotency_key:)` |
| Physical POS payments | `physical_pos.create_payment(request, idempotency_key:)`, `create_reversal(payment_id, request, idempotency_key:)`, `cancel_payment`, `get_payment`, `list_payments`, `list_transactions`, `get_transaction`, `list_ambiguous_payments` |
| Physical POS reports and end-of-day | `physical_pos.get_sales_summary`, `get_tax_summary`, `list_settlements`, `start_settlement(device_id, idempotency_key: nil)`, `list_settlement_runs`, `get_settlement_run` |
| Physical POS management | `physical_pos_management` stores, registers, terminals (bank and provider rows, device links), devices and identity keys, end-of-day policies, catalog and overview |
| Wallet | `wallet.ping`, `wallet.end_users`, `wallets`, `deposits`, `corporate`, `fees`, `transfers`, `withdrawals`, `operations`, `topups`, `payments`, `qr`, `bulk_payouts` |
| Bank accounts | `bank_connect.list_banks`, `list_connections`, `get_connection`, `list_accounts`, `get_account`, `request_sync`, `list_balances`, `list_transactions`, `get_transaction` |
| Bank transfers and FX | `bank_connect.transfers.list_purposes`, `create(request, idempotency_key: nil)`, `list`, `get`; `bank_connect.fx.list_rates`, `create_quote`, `create_order(request, idempotency_key: nil)`, `list_orders`, `get_order` |
| Sanctions screening | `sanction.screen_name`, `screen_wallet`, `screen_account`, `screen_transaction`, `screen_public_procurement_ban`, `screen_adverse_media`, monitoring, entity intelligence, `list_blacklist_entries`, `Lunixi::Sanction.clear_screening?(result)` |
| Insurance | `insurance.list_products`, `search_products`, `create_quote`, `create_order`, `bind_payment`, `confirm_payment`, `issue_policy`, `cancel_order`, `refund_premium`, policy files, reconciliation, leads |
| Subscriptions | `subscriptions.create(request, idempotency_key:)`, `get`, `list`, `cancel`, `pause`, `resume`, `change_plan`, `audit_logs`; sub-clients `plans`, `customers`, `cards`, `invoices`, `portal`, `products`, `features`, `addons`, `usage` |
| KYC / KYB / evidence | `kyc.create_session`, `get_session`, `list_sessions`, `set_jurisdiction`, `set_primary_document`, `upload_document`, `timeline`, `submit`, `manual_review`, `evidence_request`, merchant policy, webhook outbox, erasure requests |
| Identity signals | `identity.analyze_sync`, `analyze`, `account_links`, `get_session`, `related_sessions`, `timeline`, `top_sources`, `list_sessions` |
| Marketplace | `marketplace.create_checkout_intent`, `charge_marketplace_card2d`, `charge_marketplace_card3d`, sub-dealers, commissions, payouts, audit log |
| Other documented endpoints | `request(method, path, body: nil, query: {}, idempotency_key: nil, signed: true, binary: false, accept: 'application/json', max_retries: nil)` |

Every payment body carries the order details (`Lunixi::OrderDetails`): `buyer` (`name`, `surname`, `identityNumber` — Turkish ID or passport number, `email` — ASCII, `gsmNumber`, `city`, `country`, `zipCode`, `ip` — the buyer's browser IP), `billingAddress` (`contactName`, `address`, `city`, `country`, `zipCode`) and at least one `basketItems` entry (`id`, `name`, `category1`, `itemType`, `price`; the prices add up to the amount); a `PHYSICAL` item also needs `shippingAddress`. On `create_intent`, `create_marketplace_intent` and `marketplace.create_checkout_intent` `ip` may be left out (`Lunixi::CHECKOUT_INTENT_BUYER_OPTIONAL_FIELDS`): the Lunixi form takes it from the buyer's browser. `create_intent`, `create_marketplace_intent`, `direct_method_payment`, `split`, the marketplace intents and card charges, `store_card` (buyer and billing address only) and `wallet.topups.start_card` (buyer and billing address, `shippingAddress` optional) raise `ConfigurationError` naming the missing paths before sending; `Lunixi::OrderDetails.missing(body)` returns the same list (`buyer.email`, `basketItems.0.category1`, `shippingAddress`). The field lists are `Lunixi::ORDER_DETAILS_REQUIRED_FIELDS`, `Lunixi::BUYER_REQUIRED_FIELDS`, `Lunixi::ADDRESS_REQUIRED_FIELDS` and `Lunixi::BASKET_ITEM_REQUIRED_FIELDS`. The gateway answers a missing field with 400 `payment.order.field_required` and an invalid one with `payment.order.field_invalid` (`Lunixi::OrderFieldErrorCode`, `Lunixi::OrderFieldReason`).

`amount`, split `totalAmount` and each leg/item price must be positive canonical minor-unit strings within the signed 64-bit fiat range. Root `price`/`paidPrice` are removed fields and rejected even when null. Basket and split totals must agree. Each `basketItems` entry may carry the optional `productCategory`: the Lunixi product category code (for example `'MOBILE_PHONE'`), used by payment methods with legal installment limits (e.g. shopping loan) and other platform features. Leave it out to keep today's behaviour; the gateway rejects an unknown code with 400. The codes are available as `Lunixi::ProductCategory` constants (`Lunixi::ProductCategory::MOBILE_PHONE`, all 40 in `Lunixi::ProductCategory::ALL`); the list only grows by appending, so the value stays a plain string and the SDK does not check it before sending. Intent installments belong to the checkout form; `installment` is rejected on intent creation. The optional `enabledInstallments` list only narrows the installment counts the form offers for one payment (`[1]` = single payment only); the form shows only the counts your panel settings, the card and the platform maximum also allow. Leave it out for no restriction. The list must hold distinct integers 1–36 that include 1; any other list (an empty list included) raises `ConfigurationError` before sending, and the list is sent in ascending order. Set `preauth: true` for authorization, then capture separately with a new durable operation key. Omitting the capture/refund `amount:` keyword asks the gateway to use the remaining amount; explicit nil, numeric, zero, false and noncanonical string amounts are rejected.

```ruby
lunixi.payments.refund('intent_123', amount: "2500",
                      reason: 'Customer request', idempotency_key: refund.persisted_operation_key)

# Advanced transport: a documented existing endpoint, not a second HTTP stack.
banks = lunixi.request('GET', '/api/v1/bank-connect/banks', query: { limit: 20 })
```

Payments, fraud, payment links, physical POS, wallet, bank accounts, sanctions screening, insurance, subscriptions, KYC, identity signals and the marketplace have their own clients; other products use the signed transport with the published gateway schema. JSON is compact UTF-8 with JavaScript integer-index key ordering and compatible numeric formatting, so the signed bytes are exactly the transmitted bytes.

## Payment methods

`payments.list_payment_methods` (signed) returns the methods open for your account. Each method carries its `blockName`, `providerSelection` (`Lunixi::ProviderSelection`), `providerSelectionMode` (`Lunixi::ProviderSelectionMode`) and its providers with the `inputFields` to send in the method block. Always read the provider code from this response; never hard-code it. `payment_method:` narrows the list to one code (`Lunixi::PaymentMethod`); `QR` is sent as `QR_CODE` and a malformed code raises `ConfigurationError` before sending.

`payments.direct_method_payment` starts a payment with any method from your server (`POST /api/v1/payments/direct/payment`, signed). The `idempotency_key:` is required; reuse it when retrying the same payment. Build the body with `Lunixi::DirectMethodPaymentRequest` or pass a raw Hash; both are checked before sending: known fields only (`Lunixi::DIRECT_METHOD_PAYMENT_FIELDS`), exactly the block of the chosen method (`Lunixi::METHOD_BLOCK_FIELDS`, the camelCase method code), card fields (`Lunixi::CARD_ONLY_FIELDS`) only with `CARD`, the block structure (at most 32 fields; strings up to 1024 characters, numbers, booleans, `ADDRESS` objects and `GROUP` lists of up to 10 objects), the promissory-note plan and 1–100 basket items for `SHOPPING_LOAN`.

```ruby
request = Lunixi::DirectMethodPaymentRequest.new('10000', 'TRY', order.reference)
                                            .with_method_fields(Lunixi::PaymentMethod::MOBILE_BILLING, provider_code,
                                                                gsmNumber: '+905321234567')
                                            .with_buyer(buyer).with_billing_address(billing_address) # buyer includes ip here
                                            .with_basket_items(basket_items)
result = lunixi.payments.direct_method_payment(request, idempotency_key: order.payment_operation_key)

action = result.dig('data', 'action')
if action && action['type'] == Lunixi::PaymentActionType::OTP
  lunixi.payments.confirm_payment_action(result.dig('data', 'paymentId'), action['id'], otp: code_from_buyer)
end
```

`confirm_payment_action` sends only `otp` (digits), `consentAccepted` (boolean) and `fields` (the values an `INPUT` action asks for); checkout token fields are rejected. `resend_payment_action` sends a new one-time code; confirm with the new `data.action.id`. A card payment uses `with_card(card_fields)`, `with_installment(count, quote_token)` and `with_force3d(true)`.

### Promissory notes

A `PROMISSORY_NOTE` payment carries its plan: either `with_promissory_note_schedule([{ amount: '5000', dueDate: '2027-01-15' }, …])` (1–24 rows, positive minor-unit amounts adding up to `amount`, `YYYY-MM-DD` dates in order) or `with_promissory_note_count(3)`, never both. `get_promissory_notes(payment_id)` lists the notes (`Lunixi::PromissoryNoteStatus`), `cancel_promissory_notes(payment_id, serial_numbers: nil)` cancels the given notes or every open one (`Lunixi::PromissoryNoteCancelResult`, `Lunixi::PromissoryNoteCancelErrorCode`), and `download_promissory_note_document(payment_id, locale: 'tr-TR')` returns the printable PDF as a frozen binary String. Note changes arrive as `Lunixi::PromissoryNoteEvents` webhooks. `reference.list_provinces`, `list_districts` and `list_neighborhoods` return the address codes of an `ADDRESS` field.

### Bank transfer (Para Transferi)

A `BANK_TRANSFER` payment takes no provider code: send the buyer's bank as `with_method_fields(Lunixi::PaymentMethod::BANK_TRANSFER, nil, bankCode: '0062')`, or `Lunixi::BANK_TRANSFER_OTHER_BANKS_CODE` (`'9999'`) for EFT/FAST from a bank not listed. The response carries a `DISPLAY` action with the transfer instruction to show the buyer:

```ruby
instruction = Lunixi::BankTransferInstruction.from_response(result)
# instruction.iban, instruction.holder_name, instruction.amount_minor, instruction.payment_code, instruction.expires_at
```

`from_response` returns nil when the response has no `DISPLAY` transfer instruction. Late, short and excess transfers become exceptions: `list_bank_transfer_exceptions(environment: 'LIVE', status: 'PENDING_DECISION', limit: 50)`, `accept_bank_transfer_exception(id)` and `mark_bank_transfer_exception_refunded(id)` (`Lunixi::PaymentBankTransferExceptionKind`, `Lunixi::PaymentBankTransferExceptionStatus`, webhook names in `Lunixi::PaymentBankTransferEvents`).

### Split payments

The split body (`Lunixi::SPLIT_PAYMENT_FIELDS`) carries the order details with the legs: `buyer`, `billingAddress`, `basketItems` (adding up to `totalAmount`) and `shippingAddress` for a `PHYSICAL` item. A non-card split leg carries only one of `Lunixi::SPLIT_LEG_BLOCK_FIELDS` (`mobileBilling`, `wallet`, `promissoryNote`); meal card, open banking, shopping loan and bank transfer cannot be legs and are rejected before sending. `list_splits(status: 'COMPLETED', limit: 25)` lists split payments (`Lunixi::LIST_SPLIT_PAYMENTS_FILTERS`). Webhook names are in `Lunixi::SplitPaymentEvents`; add `Lunixi::SPLIT_LEG_EVENTS_SUBSCRIPTION` to an endpoint's event types to also receive leg events.

### BIN, installments and stored cards

`payments.bin_info('45438800')` returns the card and bank details of a BIN or card number prefix (6–19 digits). `payments.installment_options` returns the installment table; with a BIN and `installment` above 1 it also returns the binding `quoteToken` for `DirectMethodPaymentRequest#with_installment`. Its `enabledInstallments` follows the rule of `create_intent`. Card numbers and BINs never appear in error messages or in the `inspect` output of the request builders.

```ruby
options = lunixi.payments.installment_options(
  Lunixi::InstallmentOptionsRequest.new('10000', 'TRY').with_bin_or_pan(bin).with_enabled_installments([1, 2, 3])
)
```

`payments.store_card(Lunixi::StoreCardRequest.new(card, card_user_key, callback_url).with_buyer(buyer).with_billing_address(billing_address), idempotency_key:)` verifies and stores a card (signed; the card holder as the buyer and the billing address are required); `list_stored_cards(card_user_key)` and `get_stored_card(token)` return masked card data, and `deactivate_stored_card(token, idempotency_key:)` removes it (signed). Both writes require the idempotency key.

`payments.create_marketplace_intent` takes the intent body plus `sellers` (`[{ subDealerId:, amountMinor:, scenario: }]`) and `multiSellerPolicy`. Each `amountMinor` is a canonical minor-unit string and the sellers must add up to `amount`; any other total raises `ConfigurationError` before sending.

## Payment links

`client.payment_links` covers `/api/v1/payments/links`. Every call is signed, reads included; the signing key decides the merchant and the TEST/LIVE environment. Responses are the gateway envelope: a list has `data.items` and the top-level `pageInfo` (`hasMore`, `nextCursor`, `totalCount`).

```ruby
link = lunixi.payment_links.create(
  { usage: Lunixi::PaymentLinkUsage::SINGLE_USE, amountMode: Lunixi::PaymentLinkAmountMode::FIXED,
    currency: 'TRY', amountMinor: '150000', title: 'Invoice 42', expiresAt: Time.now + 7 * 86_400 },
  idempotency_key: invoice.link_operation_key
)
link_id = link.dig('data', 'id')
lunixi.payment_links.send_link(link_id, channel: Lunixi::PaymentLinkDeliveryChannel::EMAIL,
                                        recipient_email: 'buyer@example.com', idempotency_key: invoice.send_operation_key)
lunixi.payment_links.update(link_id, link.dig('data', 'rowVersion'), { title: 'Invoice 42 (revised)' })
```

- `create` accepts only `Lunixi::PAYMENT_LINK_SPEC_FIELDS` plus `environment`; `update` takes the link's current `rowVersion` and the changed fields (`nil` clears one) and refuses `Lunixi::PAYMENT_LINK_IMMUTABLE_FIELDS`. A `Time` in `startsAt`, `expiresAt` or `eventAt` is sent as ISO 8601 UTC.
- `create` and `send_link` require the idempotency key; `update`, `pause`, `resume` and `deactivate` take an optional one.
- `list`, `list_attempts` and `list_payments` accept their documented filters only; an Array (for `state`, `usage`, `amountMode`) is sent as a comma list.
- `qr(link_id, format: 'png', size: 512)` returns the image as a frozen binary String.

A link image is uploaded in three steps, or in one call with `upload_image`:

```ruby
image = lunixi.payment_links.upload_image(file_name: 'cover.png', content_type: Lunixi::PaymentLinkImageContentType::PNG,
                                          content: File.binread('cover.png'))
asset_id = image.dig('data', 'assetId') # use as imageAssetId
```

`create_image_upload` returns the upload target (`assetId`, `uploadUrl`, `uploadHeaders`, `expiresAt`); the bytes are then PUT to `uploadUrl`, and `confirm_image_upload(asset_id)` publishes the image. The PUT goes straight to the storage host through the configured transport with only `uploadHeaders`: it never carries the access token, the signature headers or the idempotency key. An upload target that is not HTTPS, not a `PUT` or has malformed headers raises `ApiError` before anything is uploaded. A failed PUT is not retried; it raises `ApiError` with the storage status and code (for example `AccessDenied` once the URL has expired), and `upload_image` can be called again for a new URL. Images are PNG, JPEG or WebP (never SVG), at most 2 MiB.

## Fraud decision log and event batches

`fraud.decisions.list(paymentId:, decision:, integrationMode:, productContext:, limit:, cursor:)` lists persisted decisions (`data` is the page, `pageInfo.nextCursor` the next cursor), `fraud.decisions.get(trace_id)` returns one and `fraud.decisions.latest_for_payment(payment_id)` returns the latest decision Hash of a payment or nil. `fraud.events.record_batch(events, idempotency_key:)` sends up to 500 transaction events as one signed JSON array; the batch can succeed partially, so read the per-event results in `data`.

## Physical POS

`client.physical_pos` starts and follows payments on your card terminals (`/api/v1/physical-pos`); `client.physical_pos_management` manages stores, registers, logical terminals, devices and the end-of-day policy. Every call is signed; a TEST key can only read. Body and filter keys are the wire names (String or Symbol; snake_case works too), amounts are canonical minor-unit strings and counts are numbers.

```ruby
key = Lunixi::PhysicalPos.new_idempotency_key
order.update!(pos_key: key) # store the key before you call
begin
  result = lunixi.physical_pos.create_payment(
    { operation: Lunixi::PhysicalPosPaymentOperation::SALE, target: { deviceId: device_id }, amountMinor: '4500', currency: 'TRY',
      merchantReference: order.reference, allowDuplicateReference: false },
    idempotency_key: key
  )
  result.status_code # 202 accepted (not paid yet), 200 when the same key and body were sent before
rescue Lunixi::PhysicalPosOutcomeUnknownError
  # The payment may exist: call again later with the SAME key, or find it with list_payments(merchantReference:).
end
```

- A payment write means "accepted": follow the outcome with the `physical_pos.payment.*` webhooks or `get_payment`. `create_payment` and `create_reversal` require the idempotency key (8–200 printable ASCII characters, sent exactly as given); `cancel_payment`, `start_settlement` and the keyed management writes create a UUID when you pass `nil` and return it as `idempotency_key`.
- A payment write tries 1 + `max_retries` times with the same key and body. No answer, a 5xx that does not say "not started" or a 2xx without a payment leaves the outcome unknown and ends in `PhysicalPosOutcomeUnknownError`, even when a later attempt got a 4xx. Never retry with a new key: it can charge the card twice.
- Card data is never sent; the card is read on the device. A card-data field (`pan`, `cardNumber`, `cvv`, `expiry`, `track2` …) at any depth, or a card number in `merchantReference`, an item name, a tax group or a free-text filter, raises `PhysicalPosCardDataRejectedError` before anything is sent; the error names the field, never the value. Any other unknown field or filter raises `ConfigurationError`.
- Lists return `Lunixi::PhysicalPosPage` (`items`, `has_more`, `next_cursor`, `total_count`); every list has an `iterate_*` twin that walks all pages. Updates and status changes take the `rowVersion` you last read.
- Typed errors: `PhysicalPosVoidAfterSettlementError` (`allowed_operation`, usually `REFUND`), `PhysicalPosRateLimitError` (`retry_after` in seconds), `PhysicalPosCardDataRejectedError` (`field`).

Physical POS webhooks are read through the signature check, never around it:

```ruby
event = Lunixi::PhysicalPosWebhook.parse(raw_request_bytes, signature_headers, ENV.fetch('LUNIXI_WEBHOOK_SECRET'))
case event.category
when Lunixi::PhysicalPosWebhook::CATEGORY_PAYMENT then apply_payment(event.data, event.history_seq, event.cashier)
when Lunixi::PhysicalPosWebhook::CATEGORY_SETTLEMENT then record_end_of_day(event.data) # no history_seq: deduplicate by event.id
end
```

Delivery order is not guaranteed: deduplicate by `event.id` and ignore a payment event whose `history_seq` is not greater than the last one you applied. `event.original` names a reversal's original payment, `event.cashier` the device cashier session (nil when there was none) and `event.device_sale?` a sale made directly on the device.

## Wallet

`client.wallet` is the server-to-server wallet surface (`/api/v1/wallet`). Every call is signed; the key needs the `WALLET_SERVICE` product and the wallet permission of the route. Bodies and filters are checked against `Lunixi::WALLET_ROUTES` before anything is sent: an unknown field, a missing required field, an amount that is not a minor-unit digit string (`"12550"`, never `125.5` or `12550`) or a missing `Idempotency-Key` raises `ConfigurationError`. Keys are the wire names (String or Symbol; snake_case works too).

```ruby
step = lunixi.wallet.transfers.initiate_w2w(
  { endUserId: end_user_id, sourceWalletAccountId: account_id, destinationWalletNo: wallet_no, amount: '12550', currency: 'TRY' },
  idempotency_key: transfer.initiate_key
)
lunixi.wallet.transfers.complete_w2w(step['operationId'], { endUserId: end_user_id, integrityHash: step['integrityHash'],
                                                            nonce: step['nonce'], otpCode: otp }, idempotency_key: transfer.complete_key)
```

Money moves in two steps: `initiate_*` reserves the limit, `complete_*` commits it with the same `integrityHash` and `nonce` (the SDK puts `operationId` in the body). Lists return `Lunixi::ListPage` (`items`, `next_cursor`, `has_more?`); `iterate` walks every page. `qr.image` returns the image bytes. `end_users.freeze_end_user(end_user_id, ...)` freezes an end user (named so that `Object#freeze` keeps its meaning).

## Bank accounts, transfers and FX

`client.bank_connect` reads your connected bank accounts, balances and transactions; bank connections are made in the Lunixi dashboard. Every call is signed and the key decides the environment. Filters are checked before sending: values in their sets, `limit` 1–100, at most 100 account ids, minor-unit strings for `minAmountMinor` / `maxAmountMinor`, and `bookedFrom` (inclusive) / `bookedTo` (exclusive) at most 92 days apart, `bookedTo` only with `bookedFrom`.

```ruby
page = lunixi.bank_connect.list_transactions(accountId: [account_id], bookedFrom: Time.now - 7 * 86_400, direction: 'CREDIT')
transfer = lunixi.bank_connect.transfers.create(
  { accountId: account_id, receiverIban: iban, receiverName: 'Receiver Name', amountMinor: '150075', description: 'Invoice 42' },
  idempotency_key: payout.id # 8–200 printable ASCII; a UUID v4 is generated when nil
)
```

`transfers` and `fx` need the `bank-connect:transfer` scope and a key with an IP allowlist. `transfers.create` and `fx.create_order` retry a network error or a 5xx with the same key and body; pass your own key to retry safely across processes (the same key and body answer the existing record with `replayed: true`). An answered error carries the key as `idempotency_key`. `fx.create_quote` takes exactly one of `sourceAmountMinor` / `targetAmountMinor`.

## Sanctions screening

`client.sanction` screens names, wallets, accounts and transactions, runs ongoing monitoring and reads entity intelligence. These calls carry the access token only (no request signature). Bodies and filters are checked against `Lunixi::SANCTION_ROUTES` before sending, including the nested rows and the value sets (`Lunixi::SanctionRiskDomain`, `SanctionScreenMode`, `SanctionWalletScreenMode`).

```ruby
result = lunixi.sanction.screen_name(name: 'Customer Name', riskDomains: [Lunixi::SanctionRiskDomain::SANCTIONS], customerReference: customer.id)
review!(result) unless Lunixi::Sanction.clear_screening?(result)
```

Screening returns matches, not verdicts. A result is clear only when it has no match or hit, no blocking flag or decision and, when it reports coverage, `coverageStatus` is `COMPLETE`; a screening that could not run raises `ApiError` and never looks like an empty result.

## Insurance

`client.insurance` offers, sells and services insurance for your basket items (I1–I22). Every call is signed. `create_order`, `confirm_payment`, `issue_policy`, `cancel_order`, `refund_premium` and `create_lead` require an `Idempotency-Key` (8–200 printable ASCII); `create_quote` and `bind_payment` take one optionally. The basket of a quote is either `paymentIntentId` or `context.items`, never both; the fields of an insurance type's own object are validated by the gateway (422 `insurance.validation.invalid` with every field at once).

```ruby
quote = lunixi.insurance.create_quote({ insuranceType: product['insuranceType'], currency: 'TRY', context: { items: basket_items } })
option = quote['options'].first
order = lunixi.insurance.create_order(
  { quoteId: option['quoteId'], consent: Lunixi::Insurance.consent_from_quote(option, accepted_at) }, idempotency_key: order_key
)
basket_items << Lunixi::Insurance.premium_basket_item(order, name: 'Insurance premium', category1: 'Insurance')
```

Policy documents, receipts and certificates come back as PDF bytes; `export_reconciliation` returns a `Lunixi::InsuranceReconciliationExport` (`data`, `truncated?`, `next_cursor`, `aborted?`).

Bank-account, bank-transfer and insurance webhooks are read through the signature check:

```ruby
event = Lunixi::InsuranceWebhook.parse(raw_request_bytes, signature_headers, ENV.fetch('LUNIXI_WEBHOOK_SECRET'))
record_policy(event['insuranceOrderId'], event['policies']) if event.type == Lunixi::InsuranceEvents::POLICY_ISSUED
```

`Lunixi::BankConnectWebhook` reads `bank_account.transaction.received`, `Lunixi::BankTransferWebhook` reads Bank Connect `bank_transfer.*` (not the payment method's `payment.bank_transfer.*`) and `Lunixi::InsuranceWebhook` the order events and `insurance.lead.submitted`. `event.data` holds the documented fields only; deduplicate by `event.id`.

## Subscriptions

`client.subscriptions` runs recurring billing: plans, customers (upserted by your own `externalId`), saved cards (added from the checkout SDK's `paymentMethodToken`, never a card number), subscriptions, invoices, the customer portal, catalog products, features, add-ons and metered usage. These calls carry the access token only. Creating a subscription requires an `Idempotency-Key`, which is sent in the body as well; plan, customer, card, plan-change and charge-retry writes accept one. Bodies and filters are checked against `Lunixi::SUBSCRIPTION_ROUTES` before sending, and the money members of bodies, filters and answers must be canonical minor-unit strings (`"0"` for a free plan).

```ruby
plan = lunixi.subscriptions.plans.create({ productId: product_id, code: 'pro', name: 'Pro', price: '9900', currency: 'TRY',
                                           billing: { frequency: 'MONTHLY' } }, idempotency_key: plan_key)
# Renewals take the buyer from the customer record: identity and billing details are required.
customer = lunixi.subscriptions.customers.upsert({ externalId: user.id, name: user.first_name, surname: user.last_name, email: user.email,
                                                   gsmNumber: user.phone, identityNumber: user.identity_number,
                                                   billingAddress: user.address, billingCity: user.city, billingCountry: user.country,
                                                   billingZipCode: user.zip_code })
subscription = lunixi.subscriptions.create({ customerId: customer['id'], planId: plan['id'] }, idempotency_key: signup.key)
grant_access! if Lunixi::Subscriptions.active?(subscription)
```

The subscription, plan, customer, card, invoice and audit-log lists return a `Lunixi::ListPage` whose `next_cursor` goes back as `page_token:` (`page_size` is the envelope's `pageSize`); `iterate` walks every page. `portal.create_sdk_session` returns the embedded-portal proof (`portalToken`, `sessionProof`, `proofNonce`, `proofExpiresAt`); `portal.create_portal_link` returns a hosted link, opened with `Lunixi::Subscriptions.portal_url(link)`. Event names are in `Lunixi::SubscriptionEvents`. A missing or invalid customer field is 400 `subscription.customer.field_required` / `subscription.customer.field_invalid` (`Lunixi::SubscriptionCustomerErrorCode`).

## KYC and identity signals

`client.kyc` creates and drives KYC, KYB and evidence sessions; the browser SDK runs the capture with the publishable key and the `kyc.*` webhook (`Lunixi::KycEvents`) is the authority for the result. `person:` / `company:` are sent as `customer` with its `customerType`, and `metadata:` as `evidenceContextJson`. `list_sessions` takes only `limit` and `cursor` (`pageSize` / `pageToken` are read as the same). A document image never appears in an error message.

```ruby
session = lunixi.kyc.create_session({ subjectId: user.id, sessionType: Lunixi::KycSessionType::KYC, externalCustomerId: user.id,
                                      person: { firstName: user.first_name } }, idempotency_key: kyc_key)
approved = Lunixi::Kyc.assurance_meets?(achieved_level, Lunixi::KycAssuranceLevel::SUBSTANTIAL)
```

`client.identity` reads device and account-linking signals for a browser `traceId` (risk flags and reason codes, not a verdict). `Lunixi::Identity.device_shared?(links)` tells whether another account uses the device; `Lunixi::Identity.link_reasons(links)` lists why. Both clients carry the access token only.

## Marketplace

`client.marketplace` splits a charge across sub-dealers and manages them. Split charges (`create_checkout_intent`, `charge_marketplace_card2d`, `charge_marketplace_card3d`) are signed and take an optional idempotency key (16–128 printable ASCII); pass one leg per sub-dealer, `{ subDealerId, amountMinor, scenario? }`, and the legs must add up to `amount` (checked before sending). A checkout intent answered without a token or a form raises `ApiError`. Card data is sent as given and never put in an error message; prefer the hosted form (`create_checkout_intent`) over a direct card charge.

```ruby
intent = lunixi.marketplace.create_checkout_intent(
  { amount: '100000', currency: 'TRY', orderId: order.id, callbackUrl: return_url,
    buyer: buyer, billingAddress: billing_address, basketItems: basket_items }, # order details as in Start checkout
  [{ subDealerId: 'd_alice', amountMinor: '60000' }, { subDealerId: 'd_bob', amountMinor: '40000' }],
  multi_seller_policy: Lunixi::MarketplaceMultiSellerPolicy::ALL_OR_NOTHING, idempotency_key: order.payment_key
)
```

Dealer, commission, payout and audit-log routes carry the access token only: `create_dealer`, `bulk_create_dealers`, `list_dealers`, `get_dealer`, `update_dealer_status`, `onboarding_token` (`Lunixi::Marketplace.onboarding_url(link)`), `dealer_application`, `submit_dealer_application`, `set_dealer_terms`, `sign_dealer_contract`, `activate_dealer`, `record_dealer_kyc_result`, `payout_ledger`, `transactions`, `commission_rules`, `upsert_commission_rule`, `preview_commission_rule`, `resolve_commission`, `create_payout`, `mark_payout_paid`, `bulk_mark_payouts_paid`, `audit_log` and `verify_audit_log`.

## Raw-body webhooks and durable deduplication

```ruby
verifier = Lunixi::WebhookVerifier.new(
  secret: ENV.fetch('LUNIXI_WEBHOOK_SECRET'),
  previous_secrets: [] # Up to two retained secrets during rotation.
)

verifier.process(raw_request_bytes, signature_headers, store: durable_transactional_store) do |event|
  # Correlate event.data with your persisted intent and order.
  # Query payment status, check amount/currency/final status, update atomically.
end
```

The verifier accepts only v2 HMAC-SHA256 over `eventId.timestamp.rawBody`, compares signatures in constant time, binds signed ids/types to the body, rejects malformed/duplicate JSON keys, checks both future and stale timestamps (default **300 seconds**), and supports rotated secrets/signatures. Supply the exact raw request bytes before JSON parsing. Header names are case-insensitive; duplicate headers are rejected. Verification alone never consumes an event id.

The durable store implements `process_once(id:, digest:) { … }`: insert a unique event receipt and apply business changes in **one database transaction**, return `:processed` or `:duplicate`, and raise `Lunixi::ReplayConflict` if an id arrives with different bytes. Roll back the receipt on any handler failure so redelivery can recover. An in-memory set is insufficient across processes/restarts. The [Rails sample](samples/rails/app/services/rails_replay_store.rb) provides a real database implementation with a unique `(connection_id, event_id)` index.

## Errors, retries and transport

`Lunixi::Error` is the base error. `ConfigurationError`, `SignatureError`, `TransportError`, `RedirectError`, `WebhookError`/`ReplayConflict`, and `ApiError` subclasses distinguish local, network and gateway failures. Gateway errors expose safe `status`, `code`, `request_id`, optional `retry_after` and `details` (only the `field`, `allowedOperation` and `retryAfterSeconds` identifiers); they omit bodies, credentials and remote error text. Treat timeouts as uncertain outcomes: query/reconcile the original operation, never retry using a new key.

GET/HEAD and keyed mutations may retry network failures or HTTP 429/502/503/504, at most `max_retries` (default 2, maximum 3). Each retry keeps the same body/key and creates a fresh nonce/signature. A safe 401 refreshes credentials once. Unkeyed mutations are never automatically retried. HTTP redirects are rejected, certificate verification cannot be disabled, and URL traversal/credential injection is blocked. Requests are bounded to 1 MiB and responses to 8 MiB. Net::HTTP does not inherit ambient proxy credentials; a custom enterprise transport is injectable.

For deterministic tests, inject `transport:`, `clock:` and `sleeper:`. A transport implements `call(method:, uri:, headers:, body:)` and returns `Lunixi::Response.new(status:, headers:, body:)`. `ca_file:` permits an explicit trusted CA bundle without disabling TLS verification. Reusing the SDK is thread-safe; your custom transport must also be thread-safe.

## Rails and validation

Follow [samples/rails/README.md](samples/rails/README.md) for the executable Rails integration, environment setup, migration and tests. It protects buyer routes with CSRF and demo authentication, encrypts checkout tokens, persists operation keys, and applies verified webhooks atomically. It is a reference integration, not a complete storefront or multitenant authorization system.

The informational return POST is handled by a separate bounded middleware: it discards at most 1 MiB, ignores all form fields and performs no order/session lookup, gateway call or financial write. It returns an empty fixed same-origin 303 to the authenticated GET; checkout CSRF stays enabled.

```bash
bundle exec rake test
bundle exec rubocop
bundle exec bundle-audit check --update
bundle exec brakeman --force --rails8 --path samples/rails --no-pager
bundle exec rake rails:test
gem build lunixi-sdk.gemspec
```

The SDK suite includes RFC 8032 Ed25519 and shared webhook vectors, tampering, replay/rotation, money validation, concurrent token caching, exact transmitted signatures, safe retries, and real local TLS certificate/hostname/redirect/size checks. JSON compatibility tests use Node.js as an independent implementation. Rails tests use synthetic transport fixtures and a real SQLite database; they move no funds. CI runs these checks on Ruby 3.3 and 3.4. Brakeman has one narrowly documented fixed-origin redirect false positive in `samples/rails/config/brakeman.ignore`, covered by redirect-injection tests; no broad rule is disabled.

Security: [SECURITY.md](SECURITY.md) · Contributions: [CONTRIBUTING.md](CONTRIBUTING.md) · Changes: [CHANGELOG.md](CHANGELOG.md) · MIT [license](LICENSE). Support: developer@lunixi.com.

## On-site form and optional hosted checkout

The Rails example defaults to `LUNIXI_CHECKOUT_MODE=embedded`. It renders the existing Lunixi form on the merchant page using the fixed official CDN, HTML-escaped JSON data attributes and a per-response CSP nonce. `Lunixi::Checkout.browser_config(token)` provides only the official object/mount configuration. No gateway HTML or merchant secrets are rendered.

Set `LUNIXI_CHECKOUT_MODE=hosted` explicitly for optional redirect. `Lunixi::Checkout.payment_page_url(data.fetch('paymentPageUrl'))` and the Rails redirect wrapper validate the exact backend URL: HTTPS `pay.lunixi.com/payment/` followed by a 16–4096-character ASCII opaque value, with no userinfo, port, query, fragment or controls. It can differ from the embedded token. Do not construct a URL from that token. Both modes expose the same merchant-enabled form methods, multi-card, installments and insurance; these features do not require redirecting. The existing fixed-total single-intent settlement limitation still applies.

Run `rails db:migrate` before deploying 1.0.1. New request/mode/callback and start time are persisted before network I/O; request/token/backend URL use Active Record Encryption. Retries reuse the saved body and key and stop financial dispatch after 23 hours. Existing rows are marked legacy hosted; unknown legacy requests or missing backend URLs remain reconciliation-only, without rewriting origin, resetting a key or inventing a URL. Global mode changes affect new reservations; existing requests retain their saved presentation. CSRF/demo authorization, raw webhooks, native receipt transactions and the bounded 3DS/split return adapter remain unchanged.

Historical focused 0.1.2 verification: 24 Rails form/return/URL/CSP security tests with 225 assertions, 2 SDK helper tests with 5 assertions, RuboCop and Brakeman (one exact documented strict-URL redirect false positive). Prior full 0.1.1 results remain the baseline; live/merchant acceptance is deferred.

The checkout page’s CSP permits form POSTs only to `'self'` and the configured gateway origin (default `https://api-gateway.lunixi.com`). This preserves wallet/provider and legacy POST handoffs supported by the browser SDK. For another reviewed provider, set server-only `LUNIXI_FORM_ACTION_ORIGINS` to a comma-separated list of exact HTTPS origins, without spaces, paths, trailing slashes, credentials, query, fragment or wildcards. Invalid configuration fails closed; gateway responses and browser fields never expand this list. Script nonces, frame/connect restrictions and informational return handling remain in force.

Before upgrading from 0.x, follow [the money-string migration](MIGRATION-1.0.md).
