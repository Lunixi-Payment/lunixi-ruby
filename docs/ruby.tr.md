---
title: Ruby SDK
description: Lunixi Ruby SDK — kurulum, Ed25519 imza, ödeme ve fraud, kalıcı idempotency ve özgün baytlarla v2 webhook doğrulama.
---


# Ruby SDK

`lunixi-sdk`, Lunixi için sunucu tarafı Ruby istemcisidir. Ed25519 imzayı OpenSSL ile üretir; token’ı eşzamanlı istekler arasında saklar, kompakt JavaScript uyumlu JSON oluşturur, güvenli tekrar denemeleri ve özgün baytlarla webhook doğrulamayı sağlar. Rails, Sinatra, Rack ve düz Ruby ile çalışır. Ana gem çerçeveden bağımsızdır; kaynak depodaki çalıştırılabilir [Rails örneği](/sdks/rails) ayrı adaptördür.

## Gereksinimler ve kurulum

Ruby **3.3+**, Bundler ve **Ed25519** destekli OpenSSL gerekir. Rails örneği Rails 8.1 kullanır.

1.0.1 RubyGems üzerinde kullanılabilir olduğunda Gemfile’a `gem 'lunixi-sdk', '1.0.1'` ekleyip `bundle install` çalıştırın. [Para sözleşmesi geçişini](../MIGRATION-1.0.md) uygulayın. Aşağıdaki kaynak derlemesi geliştirme için isteğe bağlıdır:


```bash
git clone --branch v1.0.1 --depth 1 https://github.com/Lunixi-Payment/lunixi-ruby.git
cd lunixi-ruby
bundle install
gem build lunixi-sdk.gemspec
gem install ./lunixi-sdk-1.0.1.gem
```

Kaynak: [Lunixi-Payment/lunixi-ruby](https://github.com/Lunixi-Payment/lunixi-ruby). İncelenmiş yerel kopyayı `gem 'lunixi-sdk', path: '/tam/yol/lunixi-ruby'` ile kullanabilirsiniz. Bundler Git kaynağı kullanırken denetlenmiş commit’i sabitleyin.

## İstemci ve anahtarlar

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

`base_url`, `https://api-gateway.lunixi.com` gibi yalnız HTTPS origin olmalıdır; kullanıcı bilgisi, path, query veya fragment içeremez. TEST/LIVE ortamını anahtar belirler. Her üye işyeri bağlantısı için tek istemci oluşturup paylaşın; token önbelleği thread-safe çalışır.

Sunucuda anahtar üretimi:

```bash
umask 077
openssl genpkey -algorithm ED25519 -out lunixi-private.pem
openssl pkey -in lunixi-private.pem -pubout -out lunixi-public.pem
```

Public anahtarı Lunixi paneline kaydedip verilen key id’yi kullanın. Özel anahtar kaynak kontrolüne ve public web dizinine girmemelidir. PKCS#8 PEM, base64 PKCS#8 DER, base64 32 bayt seed ve 64 bayt secret desteklenir. Bkz. [Kimlik doğrulama](/getting-started/authentication).

## Ödeme intent’i

İlk istekten önce ödeme denemesini ve UUID idempotency anahtarını kalıcı kaydedin. Toplamı tarayıcıdan almak yerine sunucuda hesaplayın.

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

`10_050`, 100,50 TRY’nin kuruş karşılığıdır. Intent’i kaydedin, checkout token’ını veritabanında şifreleyin. Rails örneği token’ı doğrulayıp sabit `https://pay.lunixi.com/payment/<token>` adresini kurar. Lunixi formu, üye işyerine açık yöntemleri ve uygun alternatif/çoklu kart akışlarını gösterir; kullanılabilirlik hesap ayarlarına bağlıdır. SDK ile PAN/CVV toplamayın.

> 
Intent/token, HTTP 2xx, dönüş sayfası veya ara split durumu tahsilat kanıtı değildir. İmzalı webhook’u kalıcı siparişle eşleştirin; sunucudan ödeme sorgusunda nihai durum, tutar ve para birimi uyuşmadan siparişi tamamlamayın.


Tutarlar pozitif, kanonik alt birim string olmalı ve işaretli 64 bit fiat aralığında kalmalıdır. Kök `price`/`paidPrice` null olsa bile reddedilir. Sepet ve split bacak toplamları ana toplamla aynı olmalıdır. Intent’te `installment` gönderilmez; taksit formda seçilir. `preauth: true` provizyon ister; capture ayrı işlemdir.

## Yardımcı API’ler

| İşlem | API |
| --- | --- |
| Intent | `lunixi.payments.create_intent(body, idempotency_key:)` |
| Ödeme okuma/liste | `lunixi.payments.get(id)`, `lunixi.payments.list(**filters)` |
| Açık yöntemler | `lunixi.payments.methods(payment_method: nil)` |
| Capture | `lunixi.payments.capture(id, idempotency_key:)` |
| Tam/kısmi iade | `lunixi.payments.refund(id, idempotency_key:, reason: nil)` |
| Provizyon iptali | `lunixi.payments.void(id, idempotency_key:)` |
| Split | `lunixi.payments.split(body, idempotency_key:)` |
| Split durum/iade | `lunixi.payments.get_split(id)`, `lunixi.payments.refund_split(id, amount:, idempotency_key:, reason: nil)` |
| Fraud | `lunixi.fraud.evaluate(body)`, `lunixi.fraud.record_event(body, idempotency_key:)` |
| İmzalı genel HTTP | `lunixi.request(method, path, body: nil, query: {}, idempotency_key: nil, signed: true, binary: false)` |

Capture/iade `amount:` anahtarı gönderilmezse kalan tutar kullanılır; açık `amount: nil` reddedilir. False, sıfır, sayısal değerler ve kanonik olmayan string tutar reddedilir. Her capture/iade/iptal için ayrı, kalıcı anahtar saklayın. Belgelenmiş devam eden split durumlarındaki HTTP 400 yanıtları protokol sonucu olarak döndürülür; ödenmiş sayılmaz. Yanıt zarfı korunur.

Diğer **dokümante** gateway uçları aynı imzalı transport üzerinden çağrılabilir:

```ruby
links = lunixi.request('GET', '/api/v1/payments/links', query: { limit: 20 })
```

Payment, fraud ve webhook için açık yardımcılar vardır. Diğer servisler yayımlanmış REST şemasıyla kullanılır; bu sürüm her ürün için ayrı tipli istemci sunduğunu iddia etmez.

## Webhook

JSON parse işleminden önce özgün baytları alın. Lunixi imza header’larını string değerlerle aktarın:

```ruby
verifier = Lunixi::WebhookVerifier.new(
  secret: ENV.fetch('LUNIXI_WEBHOOK_SECRET'),
  previous_secrets: []
)

verifier.process(raw_request_bytes, signature_headers, store: durable_transactional_store) do |event|
  # Intent/sipariş ve sunucu ödeme sorgusuyla mutabakat yapın.
  # Sipariş değişikliği ile olay kaydını aynı transaction içinde commit edin.
end
```

v2 HMAC-SHA256, `eventId.timestamp.rawBody` üzerinde constant-time karşılaştırılır. İmzalı kimlik/tip tutarlılığı kontrol edilir; yinelenmiş JSON anahtarları reddedilir. Varsayılan geçmiş/gelecek zaman toleransı **300 saniyedir**. Rotasyonda en fazla iki önceki secret tutulabilir. Header isimleri büyük/küçük harfe duyarsızdır; yinelenmiş header reddedilir.

Yalnız doğrulama olay kaydı oluşturmaz. Store `process_once(id:, digest:) { … }` uygular: benzersiz receipt ve sipariş değişikliği tek veritabanı transaction’ında commit edilir; `:processed` / `:duplicate` döner. Aynı kimliğin farklı baytları `Lunixi::ReplayConflict` üretir. İşleyici hatasında receipt geri alınmalıdır; yeniden teslim kurtarabilir. Kayıtları süreçler ve yeniden başlatmalar arasında koruyun. Rails örneğinde benzersiz `(connection_id, event_id)` indeksiyle gerçek veritabanı implementasyonu vardır.

## Hatalar ve tekrar deneme

Taban sınıf `Lunixi::Error`’dır. `ConfigurationError`, `SignatureError`, `TransportError`, `RedirectError`, `WebhookError` / `ReplayConflict` ve `ApiError` alt sınıfları ayrılır. API hatalarında `status`, güvenli `code` / `request_id` ve isteğe bağlı `retry_after` vardır; karşı tarafın gövdesi/hata metni eklenmez.

GET/HEAD ve idempotency anahtarlı mutation, ağ hatası veya HTTP 429/502/503/504 için varsayılan iki, en çok üç kez tekrarlanabilir. Gövde/anahtar değişmez; nonce/imza yenilenir. Güvenli 401 çağrısında token bir kez yenilenir. Anahtarsız mutation tekrarlanmaz. Belirsiz zaman aşımında özgün işlemi sorgulayın; **yeni** anahtarla tahsilat başlatmayın.

TLS sertifika/hostname doğrulaması zorunludur; yönlendirmeler ve path/credential enjeksiyonu engellenir. İstek 1 MiB, yanıt 8 MiB ile sınırlıdır. `transport:`, `clock:`, `sleeper:` testlerde enjekte edilebilir. Transport `Lunixi::Response.new(status:, headers:, body:)` döndürmeli ve TLS/yönlendirme/thread-safety koşullarını korumalıdır. `ca_file:` doğrulamayı kapatmadan özel CA sağlar; ortam proxy kimlik bilgileri otomatik aktarılmaz.

## Testler ve Rails

```bash
bundle exec rake test rails:test
bundle exec rubocop
bundle exec bundle-audit check --update
bundle exec brakeman --force --rails8 --path samples/rails --no-pager
```

Testler kriptografik vektörleri, bozulmuş imzayı, replay/rotasyonu, imzalanan baytları, tutarları, eşzamanlı token’ı, retry’ı, gerçek yerel TLS ve Rails transaction’larını kapsar. Node.js bağımsız JSON.stringify karşılaştırması sağlar. Sentetik testler para taşımaz; canlı kabul testi için kayıtlı TEST üye işyeri gerekir. [Rails rehberi](/sdks/rails) ve [güvenlik politikası](https://github.com/Lunixi-Payment/lunixi-ruby/blob/main/SECURITY.md).
