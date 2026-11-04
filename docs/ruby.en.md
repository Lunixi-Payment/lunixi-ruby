---
title: Ruby SDK
description: Lunixi Ruby SDK — installation, Ed25519 signing, payments, fraud, durable idempotency and raw-body v2 webhooks.
---


# Ruby SDK

`lunixi-sdk` is a server-side Ruby client for Lunixi. It handles OpenSSL Ed25519 request signing, synchronized token caching, compact JavaScript-compatible JSON, safe retries and raw-body webhook verification. It works with Rails, Sinatra, Rack and plain Ruby. The core gem has no framework dependency; the executable [Rails integration](/sdks/rails) is included in the source repository.

## Requirements and installation

Ruby **3.3+**, Bundler and an OpenSSL build supporting **Ed25519** are required. The Rails example uses Rails 8.1.

After 1.0.1 is available on RubyGems, add `gem 'lunixi-sdk', '1.0.1'` to your Gemfile and run `bundle install`. Follow the [money-string migration](../MIGRATION-1.0.md). The following source build is an optional development workflow:


```bash
git clone --branch v1.0.1 --depth 1 https://github.com/Lunixi-Payment/lunixi-ruby.git
cd lunixi-ruby
bundle install
gem build lunixi-sdk.gemspec
gem install ./lunixi-sdk-1.0.1.gem
```

Source: [Lunixi-Payment/lunixi-ruby](https://github.com/Lunixi-Payment/lunixi-ruby). An application may also use a reviewed local checkout with `gem 'lunixi-sdk', path: '/absolute/path/to/lunixi-ruby'`. Pin an audited commit if you use a Bundler Git source.

## Client and keys

```ruby
require 'lunixi'

lunixi = Lunixi::Client.new(
  base_url: ENV.fetch('LUNIXI_BASE_URL'),
  key_id: ENV.fetch('LUNIXI_KEY_ID'),
  private_key: File.read(ENV.fetch('LUNIXI_PRIVATE_KEY_PATH')),
  timeout: 30,
  max_retries: 2
)
```

`base_url` must be an HTTPS origin such as `https://api-gateway.lunixi.com`, without credentials, a path, query or fragment. The key determines TEST/LIVE behavior. Create one client per merchant connection and reuse it across requests; the token cache is thread-safe.

Generate an Ed25519 key on your server:

```bash
umask 077
openssl genpkey -algorithm ED25519 -out lunixi-private.pem
openssl pkey -in lunixi-private.pem -pubout -out lunixi-public.pem
```

Register the public key in the Lunixi dashboard and use the resulting key id. Keep the private key outside source control and the public web root. Supported private-key encodings are PKCS#8 PEM, base64 PKCS#8 DER, or a base64 32-byte seed / 64-byte secret. See [Authentication](/getting-started/authentication).

## Payment intent

Persist the payment attempt and its UUID idempotency key before the first request. Calculate prices on your server, not from a browser total.

```ruby
result = lunixi.payments.create_intent(
  {
    amount: "10050",
    currency: 'TRY',
    orderId: order.public_id,
    callbackUrl: 'https://merchant.example/payments/return',
    basketItems: [{ id: 'item-1', name: 'Product', itemType: 'PHYSICAL', price: "10050" }]
  },
  idempotency_key: order.persisted_payment_attempt_key
)

intent_id = result.fetch('data').fetch('paymentId')
checkout_token = result.fetch('data').fetch('token')
```

`10_050` means 100.50 TRY in kuruş. Persist the returned intent and encrypt the checkout token at rest. The Rails sample validates the token and builds the fixed-origin hosted checkout address `https://pay.lunixi.com/payment/<token>`. The hosted form shows methods enabled for that merchant, including eligible alternative methods and multi-card flows; availability depends on account configuration. Do not collect PAN/CVV with this SDK.

> 
An intent/token, HTTP 2xx, return URL or intermediate split state does not prove capture. Correlate a verified webhook with the persisted order and authenticate a payment status read; confirm final status, amount and currency before fulfillment.


Amounts must be positive canonical minor-unit strings within the signed 64-bit fiat range. Root `price` and `paidPrice` are rejected even when null. Basket prices and split leg amounts must equal the relevant total. Intent `installment` is rejected because installments are selected in the checkout form; the optional `enabledInstallments` list (distinct integers 1–36 including 1, ascending; `[1]` = single payment only) only narrows the counts the form offers for one payment. `preauth: true` requests authorization; capture is a separate operation.

## Available helpers

| Operation | API |
| --- | --- |
| Create an intent | `lunixi.payments.create_intent(body, idempotency_key:)` |
| Read/list payments | `lunixi.payments.get(id)`, `lunixi.payments.list(**filters)` |
| Merchant methods | `lunixi.payments.methods(payment_method: nil)` |
| Capture | `lunixi.payments.capture(id, idempotency_key:)` |
| Full/partial refund | `lunixi.payments.refund(id, idempotency_key:, reason: nil)` |
| Void | `lunixi.payments.void(id, idempotency_key:)` |
| Split payment | `lunixi.payments.split(body, idempotency_key:)` |
| Split status/refund | `lunixi.payments.get_split(id)`, `lunixi.payments.refund_split(id, amount:, idempotency_key:, reason: nil)` |
| Fraud | `lunixi.fraud.evaluate(body)`, `lunixi.fraud.record_event(body, idempotency_key:)` |
| Advanced signed HTTP | `lunixi.request(method, path, body: nil, query: {}, idempotency_key: nil, signed: true, binary: false)` |

Omit the capture/refund `amount:` keyword to use the remaining amount. Explicit nil, false, zero, numeric and noncanonical string amounts are rejected. Persist a separate operation key for each capture, refund or void. Running split HTTP 400 protocol responses are returned only for documented running states; they remain pending, not paid. Response envelopes are preserved.

The advanced transport supports other **documented** gateway routes without a second HTTP implementation:

```ruby
links = lunixi.request('GET', '/api/v1/payments/links', query: { limit: 20 })
```

Payment, fraud and webhooks have explicit helpers. Other services require their published REST schema; this version does not provide a separate typed client for every product.

## Webhooks

Get the exact raw request bytes before parsing JSON. Pass the Lunixi signature headers as strings:

```ruby
verifier = Lunixi::WebhookVerifier.new(
  secret: ENV.fetch('LUNIXI_WEBHOOK_SECRET'),
  previous_secrets: []
)

verifier.process(raw_request_bytes, signature_headers, store: durable_transactional_store) do |event|
  # Reconcile event.data with the persisted intent/order and payment status.
  # Commit the business change in the same transaction as the event receipt.
end
```

The verifier requires v2 HMAC-SHA256 over `eventId.timestamp.rawBody`, uses constant-time comparison, checks signed id/type consistency, rejects duplicate JSON keys, and accepts timestamps within **300 seconds** by default, including future skew. Up to two previous secrets support rotation. Header names are case-insensitive; duplicate headers are rejected.

Verification alone does not record receipt. Your store implements `process_once(id:, digest:) { … }`: insert a unique event receipt and update the order in one database transaction, return `:processed` / `:duplicate`, and raise `Lunixi::ReplayConflict` for the same id with different bytes. Handler failure must roll back the receipt, allowing redelivery. Retain receipts across process restarts. The Rails example includes a real database store and unique `(connection_id, event_id)` index.

## Errors and retries

`Lunixi::Error` is the base class. `ConfigurationError`, `SignatureError`, `TransportError`, `RedirectError`, `WebhookError` / `ReplayConflict`, and `ApiError` subclasses distinguish failure types. API errors expose `status`, safe `code` / `request_id`, and optional `retry_after`; remote payloads and error text are omitted.

GET/HEAD and idempotency-keyed mutations may retry network errors or HTTP 429/502/503/504, default two retries and maximum three. Retries preserve the body and key while refreshing the nonce/signature. A safe 401 refreshes the token once. Unkeyed mutations are not retried. An uncertain timeout requires reconciliation with the **original** key, never a new charge key.

TLS peer/hostname verification is mandatory; redirects and path/credential injection are rejected. The request limit is 1 MiB; response limit is 8 MiB. `transport:`, `clock:` and `sleeper:` can be injected for deterministic testing. A custom transport returns `Lunixi::Response.new(status:, headers:, body:)` and must preserve TLS, redirect and thread-safety guarantees. `ca_file:` accepts an explicit trust bundle without disabling verification. Ambient proxy credentials are not inherited.

## Testing and Rails

```bash
bundle exec rake test rails:test
bundle exec rubocop
bundle exec bundle-audit check --update
bundle exec brakeman --force --rails8 --path samples/rails --no-pager
```

The suite covers cryptographic vectors, tampering, replay/rotation, exact signed bytes, money, concurrent token caching, retries, real local TLS and Rails database transactions. Node.js supplies an independent JSON.stringify comparison. Tests use synthetic fixtures and move no funds; a registered TEST merchant is needed for a live acceptance run. See the [Rails guide](/sdks/rails) and repository [security policy](https://github.com/Lunixi-Payment/lunixi-ruby/blob/main/SECURITY.md).
