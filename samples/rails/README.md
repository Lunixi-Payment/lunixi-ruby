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

Open `http://localhost:3000/orders/00000000-0000-4000-8000-000000000001`, log in with the configured demo credentials, and choose Pay. The seeded order is **100.50 TRY**. The form posts a CSRF token; the server ignores browser-provided prices. For Turkish UI append `?locale=tr`. The merchant's form settings determine which payment methods appear.

Register `https://<your-public-host>/webhooks/lunixi` in the Lunixi dashboard, subscribe to the documented payment events, and configure the matching webhook secret. Route the tunnel/proxy to the same app. The return route only shows persisted order state; webhook delivery is a separate request.

A separate middleware also accepts only `POST /orders/{public_id}/return`: it bounds the discarded raw body to 1 MiB, ignores every field, performs no order/session lookup, gateway request or financial write, and returns an empty fixed same-origin 303 to the existing authenticated GET. This informational adapter does not use the webhook secret. Checkout retains Rails CSRF and authentication; the normal GET still requires demo authentication, to be replaced with your customer/order authorization before production.

## State and security behavior

- `Order.checkout_key` is persisted before gateway access and reused after uncertainty. `checkout_token` uses Active Record Encryption. `intent_id` and the order's public UUID bind callback correlation.
The existing form opens on the merchant website by default. Optional hosted checkout uses the exact validated backend `paymentPageUrl`, independently of the embedded token. Encrypt the token and URL; both modes share the merchant-enabled form methods. Never collect PAN/CVV.
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

Only explicitly configured hosted reservations bind `metadata.allowedOrigin` to `https://pay.lunixi.com`; embedded checkout uses the merchant form origin. Existing reservations retain their original request.

## On-site form and optional hosted checkout

The Rails example defaults to `LUNIXI_CHECKOUT_MODE=embedded`. It renders the existing Lunixi form on the merchant page using the fixed official CDN, HTML-escaped JSON data attributes and a per-response CSP nonce. `Lunixi::Checkout.browser_config(token)` provides only the official object/mount configuration. No gateway HTML or merchant secrets are rendered.

Set `LUNIXI_CHECKOUT_MODE=hosted` explicitly for optional redirect. `Lunixi::Checkout.payment_page_url(data.fetch('paymentPageUrl'))` and the Rails redirect wrapper validate the exact backend URL: HTTPS `pay.lunixi.com/payment/` followed by a 16–4096-character ASCII opaque value, with no userinfo, port, query, fragment or controls. It can differ from the embedded token. Do not construct a URL from that token. Both modes expose the same merchant-enabled form methods, multi-card, installments and insurance; these features do not require redirecting. The existing fixed-total single-intent settlement limitation still applies.

Run `rails db:migrate` before upgrading the Rails sample. New request/mode/callback and start time are persisted before network I/O; request/token/backend URL use Active Record Encryption. Retries reuse the saved body and key and stop financial dispatch after 23 hours. Existing rows are marked legacy hosted; unknown legacy requests or missing backend URLs remain reconciliation-only, without rewriting origin, resetting a key or inventing a URL. Global mode changes affect new reservations; existing requests retain their saved presentation. CSRF/demo authorization, raw webhooks, native receipt transactions and the bounded 3DS/split return adapter remain unchanged.

Historical 0.1.2 verification: 24 Rails form/return/URL/CSP security tests with 225 assertions, 2 SDK helper tests with 5 assertions, RuboCop and Brakeman (one exact documented strict-URL redirect false positive). Prior full 0.1.1 results remain the baseline; live/merchant acceptance is deferred.

The checkout page’s CSP permits form POSTs only to `'self'` and the configured gateway origin (default `https://api-gateway.lunixi.com`). This preserves wallet/provider and legacy POST handoffs supported by the browser SDK. For another reviewed provider, set server-only `LUNIXI_FORM_ACTION_ORIGINS` to a comma-separated list of exact HTTPS origins, without spaces, paths, trailing slashes, credentials, query, fragment or wildcards. Invalid configuration fails closed; gateway responses and browser fields never expand this list. Script nonces, frame/connect restrictions and informational return handling remain in force.

Checkout sayfasının CSP’si form POST’u için yalnız `'self'` ve yapılandırılan gateway origin’ine (varsayılan `https://api-gateway.lunixi.com`) izin verir. Böylece tarayıcı SDK’sının desteklediği cüzdan/sağlayıcı ve eski POST geçişleri korunur. İncelenmiş başka bir sağlayıcı gerekiyorsa yalnız sunucuda `LUNIXI_FORM_ACTION_ORIGINS` tanımlayın: virgülle ayrılmış tam HTTPS origin’leri; boşluk, yol, sondaki slash, kullanıcı bilgisi, sorgu, fragment ve wildcard kabul edilmez. Geçersiz ayar reddedilir; gateway yanıtı veya tarayıcı alanı listeyi genişletemez. Script nonce, frame/connect sınırları ve bilgilendirici dönüş güvenliği korunur.
