<p align="center"><img src=".github/assets/lunixi-logo.svg" width="300" alt="Lunixi"></p>

# Lunixi Ruby SDK

[English](README.md) · [Türkçe](README.tr.md) · [Documentation](https://docs.lunixi.com/sdks/ruby) · [Rails sample](samples/rails)

Server-side Ruby client for Lunixi payments, fraud and signed gateway requests. It signs requests with OpenSSL Ed25519, caches tokens across threads, preserves integer minor-unit amounts, retries safe operations with the same idempotency key, and verifies raw-body v2 webhooks. Private keys and card details stay out of the browser and application logs.

## Requirements and installation

Ruby **3.3+**, OpenSSL with **Ed25519** support, and Bundler. The runnable Rails sample uses **Rails 8.1** and SQLite. The core gem does not depend on Rails.

Version **0.1.2** is [published on RubyGems](https://rubygems.org/gems/lunixi-sdk/versions/0.1.2). Add the exact version to your application's `Gemfile`, then run `bundle install`:

```ruby
source 'https://rubygems.org'
gem 'lunixi-sdk', '0.1.2'
```

Keep `Gemfile.lock` to retain the reviewed dependency resolution. To build the reviewed source instead:

```bash
git clone --branch v0.1.2 --depth 1 https://github.com/Lunixi-Payment/lunixi-ruby.git
cd lunixi-ruby
bundle install
gem build lunixi-sdk.gemspec
gem install ./lunixi-sdk-0.1.2.gem
```

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
    amount: 10_050, # 100.50 TRY; integer kuruş, never 100.50
    currency: 'TRY',
    orderId: order.public_id,
    callbackUrl: 'https://merchant.example/payments/return',
    basketItems: [{ id: 'item-1', name: 'Product', itemType: 'PHYSICAL', price: 10_050 }]
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
| Enabled methods | `payments.methods(payment_method: nil)` |
| Capture/preauthorization | `payments.capture(id, idempotency_key:, amount: nil)` |
| Full/partial refund | `payments.refund(id, idempotency_key:, amount: nil, reason: nil)` |
| Void authorization | `payments.void(id, idempotency_key:)` |
| Split payment (1–5 legs) | `payments.split(body, idempotency_key:)` |
| Split status/refund | `payments.get_split(id)`, `payments.refund_split(id, amount:, idempotency_key:, reason: nil)` |
| Fraud decision | `fraud.evaluate(body)` |
| Fraud transaction event | `fraud.record_event(body, idempotency_key:)` |
| Other documented endpoints | `request(method, path, body: nil, query: {}, idempotency_key: nil, signed: true, binary: false)` |

`amount`, split `totalAmount` and each leg/item price must be positive integers within JavaScript's safe integer range. Root `price`/`paidPrice` are removed fields and rejected even when null. Basket and split totals must agree. Intent installments belong to the checkout form; `installment` is rejected on intent creation. Set `preauth: true` for authorization, then capture separately with a new durable operation key. A nil capture/refund amount asks the gateway to use the remaining amount; zero, false, fractional and string amounts are rejected.

```ruby
lunixi.payments.refund('intent_123', amount: 2_500,
                      reason: 'Customer request', idempotency_key: refund.persisted_operation_key)

# Advanced transport: a documented existing endpoint, not a second HTTP stack.
links = lunixi.request('GET', '/api/v1/payments/links', query: { limit: 20 })
```

Payment, fraud and webhook helpers are explicit. Other products use the signed transport with the published gateway schema; version 0.1.2 does not claim full typed service-client parity with the PHP SDK. JSON is compact UTF-8 with JavaScript integer-index key ordering and compatible numeric formatting, so the signed bytes are exactly the transmitted bytes.

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

`Lunixi::Error` is the base error. `ConfigurationError`, `SignatureError`, `TransportError`, `RedirectError`, `WebhookError`/`ReplayConflict`, and `ApiError` subclasses distinguish local, network and gateway failures. Gateway errors expose safe `status`, `code`, `request_id` and optional `retry_after`; they omit bodies, credentials and remote error text. Treat timeouts as uncertain outcomes: query/reconcile the original operation, never retry using a new key.

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

Run `rails db:migrate` before deploying 0.1.2. New request/mode/callback and start time are persisted before network I/O; request/token/backend URL use Active Record Encryption. Retries reuse the saved body and key and stop financial dispatch after 23 hours. Existing rows are marked legacy hosted; unknown legacy requests or missing backend URLs remain reconciliation-only, without rewriting origin, resetting a key or inventing a URL. Global mode changes affect new reservations; existing requests retain their saved presentation. CSRF/demo authorization, raw webhooks, native receipt transactions and the bounded 3DS/split return adapter remain unchanged.

Focused 0.1.2 verification: 24 Rails form/return/URL/CSP security tests with 225 assertions, 2 SDK helper tests with 5 assertions, RuboCop and Brakeman (one exact documented strict-URL redirect false positive). Prior full 0.1.1 results remain the baseline; live/merchant acceptance is deferred.

The checkout page’s CSP permits form POSTs only to `'self'` and the configured gateway origin (default `https://api-gateway.lunixi.com`). This preserves wallet/provider and legacy POST handoffs supported by the browser SDK. For another reviewed provider, set server-only `LUNIXI_FORM_ACTION_ORIGINS` to a comma-separated list of exact HTTPS origins, without spaces, paths, trailing slashes, credentials, query, fragment or wildcards. Invalid configuration fails closed; gateway responses and browser fields never expand this list. Script nonces, frame/connect restrictions and informational return handling remain in force.
