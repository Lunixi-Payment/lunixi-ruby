---
title: Rails
description: Runnable Rails integration for the Lunixi Ruby SDK — hosted checkout, encrypted tokens, CSRF, durable webhook deduplication and payment reconciliation.
---


# Rails

The [Ruby SDK](/sdks/ruby) includes an executable Rails 8.1 reference application at `samples/rails`. It creates a hosted checkout with server-calculated totals, stores its token encrypted, protects buyer routes with CSRF and demo authentication, and commits verified webhook receipts and order changes atomically.

This is a **single-merchant fixed-total TRY** example. It is a source integration, not a separately published Rails gem or a complete storefront. Request signing, token caching, retries and webhook cryptography remain in `lunixi-sdk`.

## Install

Ruby 3.3+, Bundler, OpenSSL with Ed25519, and SQLite are required. Node.js is needed for the SDK's independent JSON compatibility tests.

```bash
git clone https://github.com/Lunixi-Payment/lunixi-ruby.git
cd lunixi-ruby
bundle install
```

The repository Gemfile loads the local SDK and installs Rails, Puma and SQLite. No RubyGems publication of `lunixi-sdk` is assumed. See the [sample source](https://github.com/Lunixi-Payment/lunixi-ruby/tree/main/samples/rails).

## Configure secrets

Export the following through your shell or secret manager before boot. The application does not auto-load dotenv; the repository includes `samples/rails/.env.example` as a checklist.

| Variable | Purpose |
| --- | --- |
| `LUNIXI_BASE_URL` | HTTPS gateway origin, normally `https://api-gateway.lunixi.com` |
| `LUNIXI_KEY_ID` | Registered merchant TEST/LIVE key id |
| `LUNIXI_MERCHANT_ID` | Merchant UUID that must match the authenticated payment response |
| `LUNIXI_PRIVATE_KEY_PATH` | Private Ed25519 key file outside the public web root |
| `LUNIXI_WEBHOOK_SECRET` | Secret matching the registered webhook connection |
| `PUBLIC_ORIGIN` | Public HTTPS origin of this Rails app, without a path |
| `DEMO_USERNAME`, `DEMO_PASSWORD` | Demo HTTP Basic authentication; password at least 16 bytes |
| `SECRET_KEY_BASE` | Stable Rails session secret |
| `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` | Stable primary encryption key |
| `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` | Independent deterministic encryption key |
| `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` | Independent derivation salt |

Generate a session secret locally with `ruby -rsecurerandom -e 'puts SecureRandom.hex(64)'`. Generate three additional independent 32-byte random values for encryption configuration. Save them securely and retain them across restarts. Plan Rails encryption key rotation before replacing any key; discarding an old key makes saved tokens unreadable.

A local HTTPS tunnel can supply `PUBLIC_ORIGIN`. The origin is used for the return URL and allowed-host validation. Configure it before launching the app. Do not publish a development server without authentication.

## Start a payment

```bash
cd samples/rails
bundle exec rails db:migrate db:seed
bundle exec rails server -b 127.0.0.1
```

Visit `http://localhost:3000/orders/00000000-0000-4000-8000-000000000001`, authenticate with the demo credentials and select Pay. The synthetic seeded order is **100.50 TRY**. Add `?locale=tr` for Turkish UI.

The checkout POST requires a CSRF token and reads amount/currency from the database. A UUID `checkout_key` is saved on the order before contacting Lunixi. The request uses that key, stores `intent_id`, encrypts `checkout_token` with Active Record Encryption, then redirects with HTTP 303 to the fixed host `pay.lunixi.com`. Fresh and reused tokens must pass an anchored ASCII allowlist; no browser/gateway value can supply another host or scheme.

If the network fails, the order stays pending and retains its attempt key. Repeating checkout uses the same key. A persisted token is reused; the example never clears an uncertain attempt and silently creates a new charge. Expired or unknown attempts need explicit reconciliation.

The Lunixi hosted form determines the methods available to that merchant, including eligible alternative methods and multi-card flows. The merchant application never handles PAN/CVV.

## Register the webhook

Register this URL in the Lunixi dashboard and configure the matching webhook secret:

```text
https://<your-public-host>/webhooks/lunixi
```

Subscribe to the documented payment events. The external `WebhooksController < ActionController::API` uses exact `request.raw_post` bytes and no browser session. A separate middleware also accepts only `POST /orders/{public_id}/return`: it bounds the discarded raw body to 1 MiB, ignores every field, performs no order/session lookup, gateway request or financial write, and returns an empty fixed same-origin 303 to the existing authenticated GET. This informational adapter does not use the webhook secret. Checkout retains Rails CSRF and authentication; the normal GET still requires demo authentication, to be replaced with your customer/order authorization before production.

The SDK verifies v2 signature, timestamp, event id/type and rotation. `RailsReplayStore` then inserts a receipt with a unique `(connection_id, event_id)` constraint inside the **same database transaction** as order changes. An identical duplicate returns 200 without applying fulfillment twice. Different bytes under the same id return 400. Any handler/status-query failure rolls back the receipt and returns 503 so redelivery can recover.

## Confirm settlement

`WebhookProcessor` acts on `payment.captured` only when the event identifies the stored order and intent. It authenticates `payments.get(intent_id)` and requires:

- final status `CAPTURED`;
- the same persisted order reference and intent;
- the same currency;
- the exact integer order amount.

Only then is the order marked `paid`. A failed, authorized, unknown or inconsistent result remains pending. Other subscribed events are recorded without inferring payment success. The browser return route only redirects to the persisted order state, ignoring client `status` or `paid` parameters.

> 
The SDK supports split, capture and refund requests. This sample fulfils fixed-total single-intent TRY orders. Split aggregate settlement, partial fulfillment, customer-paid insurance and surcharges require an explicit accounting/reconciliation extension before they are enabled here. A mismatched total fails closed.


## Adapt to your application

Replace demo HTTP Basic with your customer/session/tenant/order ownership checks. Preserve server-owned totals, persistent per-operation keys and atomic receipt/business transactions. Add a durable reconciliation worker for missing webhooks and uncertain outcomes, retaining the same correlation data.

The sample uses SQLite. To change the production database, install its Rails adapter and repeat transaction/concurrency checks. Long gateway reads inside database transactions simplify the example but limit throughput; a production outbox/state machine may use shorter transactions while preserving atomic event receipt and business updates.

HTTPS is forced outside local/test environments. Request info logging is disabled because Rails includes redirect URLs, which contain checkout credentials. Never log raw payment/webhook payloads or secrets. Use stable session/encryption secrets and a persistent database.

## Tests and security

From the repository root:

```bash
bundle exec rake test rails:test
bundle exec rubocop
bundle exec bundle-audit check --update
bundle exec brakeman --force --rails8 --path samples/rails --no-pager
gem build lunixi-sdk.gemspec
```

Rails tests use synthetic transport responses and a real SQLite database; no merchant credentials or fund movement are required. They cover authentication, CSRF, encrypted tokens, durable keys, redirect injection, browser-return distrust, signatures, deduplication, wrong totals/order references and rollback/redelivery. Brakeman's single weak fixed-origin redirect false positive has a precise fingerprint, review rationale and attack regression tests in `samples/rails/config/brakeman.ignore`. No security category is disabled globally.

Before launch, run an authorized TEST-merchant end-to-end payment, webhook and refund acceptance test. See the repository [README](https://github.com/Lunixi-Payment/lunixi-ruby/tree/main/samples/rails) and [security policy](https://github.com/Lunixi-Payment/lunixi-ruby/blob/main/SECURITY.md).
