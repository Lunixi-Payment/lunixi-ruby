# Rails integration / Rails entegrasyonu

Runnable **Rails 8.1 / Ruby 3.3+** reference for the local `lunixi-sdk` gem. English is the source UI; `?locale=tr` selects Turkish. This is a single-merchant, fixed-total TRY payment example, not a complete storefront.

## Run locally

From the repository root:

```bash
bundle install
ruby -rsecurerandom -e 'puts SecureRandom.hex(64)'
```

Store the generated value as `SECRET_KEY_BASE`. Generate three additional independent random values (32 bytes each) for `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`, `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY`, and `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT`. Keep these stable across restarts and manage rotations through Rails encryption key rotation; replacing a key without retaining the old key makes saved checkout tokens unreadable.

Export all variables from [.env.example](.env.example) through your shell or secret manager. This example does **not** auto-load `.env`. Supply a registered Lunixi TEST key, the matching private-key file and webhook secret. `DEMO_PASSWORD` must be at least 16 bytes. `PUBLIC_ORIGIN` is the externally reachable **HTTPS origin** of this Rails app (a development tunnel is acceptable); it is used for the return URL and allowed-host validation. Never expose a development server publicly without authentication.

```bash
cd samples/rails
bundle exec rails db:migrate db:seed
bundle exec rails server -b 127.0.0.1
```

Open `http://localhost:3000/orders/00000000-0000-4000-8000-000000000001`, log in with the configured demo credentials, and choose Pay. The seeded order is **100.50 TRY**. The form posts a CSRF token; the server ignores browser-provided prices. For Turkish UI append `?locale=tr`. The merchant's hosted-form settings determine which payment methods appear.

Register `https://<your-public-host>/webhooks/lunixi` in the Lunixi dashboard, subscribe to the documented payment events, and configure the matching webhook secret. Route the tunnel/proxy to the same app. The return route only shows persisted order state; webhook delivery is a separate request.

A separate middleware also accepts only `POST /orders/{public_id}/return`: it bounds the discarded raw body to 1 MiB, ignores every field, performs no order/session lookup, gateway request or financial write, and returns an empty fixed same-origin 303 to the existing authenticated GET. This informational adapter does not use the webhook secret. Checkout retains Rails CSRF and authentication; the normal GET still requires demo authentication, to be replaced with your customer/order authorization before production.

## State and security behavior

- `Order.checkout_key` is persisted before gateway access and reused after uncertainty. `checkout_token` uses Active Record Encryption. `intent_id` and the order's public UUID bind callback correlation.
- A fixed-origin URL builder validates fresh and stored checkout tokens before redirecting to `https://pay.lunixi.com/payment/<token>`. Logs at info level are disabled because Rails logs redirect locations. Never add raw request/response logging.
- Buyer routes use HTTP Basic **demo** authentication and Rails CSRF. Replace demo authentication with your app's customer/tenant/order ownership checks before production. `WebhooksController < ActionController::API` uses raw bytes, no browser cookie session and no global CSRF exemption.
- A unique `(connection_id, event_id)` receipt and the order update commit in one database transaction. Duplicate identical events return 200 without fulfillment twice; changed bytes under the same id return 400. Handler failures roll back both and return 503 for redelivery.
- A `payment.captured` event is correlated to the persisted intent/order. An authenticated payment GET must confirm `CAPTURED`, exact integer amount, currency and order reference before the order becomes paid. Failure, preauthorization, unknown and inconsistent results remain pending. A browser return can never mark an order paid.
- This sample intentionally fulfils **fixed-total single-intent TRY orders**. The SDK exposes split/capture/refund APIs, but split aggregate settlement, partial fulfillment, customer-paid insurance and surcharges need explicit accounting/reconciliation policy before enabling them here. A nonmatching total fails closed.
- TLS is forced outside local/test environments. Set an actual `PUBLIC_ORIGIN`, stable encryption/session secrets, an appropriately configured persistent database and a real authorization model before deployment. For a different database install its Rails adapter and rerun transaction/concurrency tests; this repository tests SQLite.

Long network calls inside the order/receipt transaction trade throughput for a simple atomic sample. Production applications may use an outbox/state machine with short transactions, preserving receipt+business-change atomicity and durable reconciliation. Unknown/expired checkout attempts require explicit reconciliation; never erase the key and create another charge blindly.

## Automated checks

No merchant credentials are needed for the offline Rails tests; synthetic test secrets are created in the test helper:

```bash
# repository root
bundle exec rake rails:test
bundle exec brakeman --force --rails8 --path samples/rails --no-pager
```

Tests use a real SQLite database and exercise authentication/CSRF, integer totals, encrypted tokens, stable keys, fixed-origin redirects, browser-return distrust, signed webhooks, duplicate events and rollback/redelivery after gateway failure or amount mismatch. The one weak fixed-origin redirect false positive is precisely documented in `config/brakeman.ignore`, with injection regression tests.

## Türkçe kurulum özeti

Kök dizinde `bundle install` çalıştırın; `.env.example` içindeki değişkenleri shell veya secret manager üzerinden dışa aktarın. `.env` otomatik yüklenmez. Geçerli TEST anahtarı, private-key dosyası, webhook secret, HTTPS `PUBLIC_ORIGIN`, en az 16 bayt `DEMO_PASSWORD`, kalıcı `SECRET_KEY_BASE` ve üç bağımsız Rails şifreleme anahtarı gerekir. Ardından `samples/rails` altında `bundle exec rails db:migrate db:seed` ve `bundle exec rails server -b 127.0.0.1` çalıştırın.

Örnek sipariş adresinin sonuna `?locale=tr` ekleyin. Lunixi panelinde `/webhooks/lunixi` adresini kaydedin. Dönüş POST adaptörü en fazla 1 MiB ham gövdeyi atar; hiçbir alanı yorumlamadan, sipariş/oturum sorgusu veya mali yazım olmadan kimliği doğrulanmış GET adresine sabit 303 verir. Checkout CSRF koruması sürer. Kullanıcı dönüşü ödeme kanıtı değildir; imzalı webhook ve tutar/para birimi/sipariş/nihai durum sorgusu birlikte doğrulanır. Demo kimlik doğrulamasını üretimde gerçek kullanıcı ve sipariş yetkilendirmesiyle değiştirin. Testler para taşımaz; canlıya geçmeden yetkili TEST üye işyeri ile uçtan uca kabul testi yapılmalıdır.

Set `LUNIXI_MERCHANT_ID` to the merchant UUID from your Lunixi account. The authenticated payment read must match this merchant, the saved payment ID, order, currency and complete settlement balances. Hosted checkout requests explicitly bind `metadata.allowedOrigin` to `https://pay.lunixi.com`.
