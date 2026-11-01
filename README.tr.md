<p align="center"><img src=".github/assets/lunixi-logo.svg" width="300" alt="Lunixi"></p>

# Lunixi Ruby SDK

[English](README.md) · [Türkçe](README.tr.md) · [Dokümantasyon](https://docs.lunixi.com/tr/sdks/ruby) · [Rails örneği](samples/rails)

Lunixi ödemeleri, fraud işlemleri ve imzalı gateway çağrıları için sunucu tarafı Ruby SDK’sı. Ed25519 imzasını OpenSSL ile üretir; token’ı eşzamanlı istekler arasında önbelleğe alır, tutarları kanonik alt birim string olarak korur ve güvenli tekrar denemelerde aynı idempotency anahtarını kullanır. v2 webhook doğrulaması özgün istek baytları üzerinden yapılır.

## Gereksinimler ve kurulum

Ruby **3.3+**, **Ed25519** destekli OpenSSL ve Bundler gerekir. Çalıştırılabilir örnek **Rails 8.1** ve SQLite kullanır; ana gem Rails’e bağımlı değildir.

1.0.1 [RubyGems](https://rubygems.org/gems/lunixi-sdk) üzerinde kullanılabilir olduğunda `Gemfile` dosyanıza tam sürümü ekleyip `bundle install` çalıştırın. [Para sözleşmesi geçişini](MIGRATION-1.0.md) uygulayın:

```ruby
source 'https://rubygems.org'
gem 'lunixi-sdk', '1.0.1'
```

İncelenen bağımlılık çözümünü korumak için `Gemfile.lock` dosyasını saklayın. Kaynak koddan kurulum alternatifi:

```bash
git clone --branch v1.0.1 --depth 1 https://github.com/Lunixi-Payment/lunixi-ruby.git
cd lunixi-ruby
bundle install
gem build lunixi-sdk.gemspec
gem install ./lunixi-sdk-1.0.1.gem
```

Bu dizinde `bundle exec ruby …` yerel SDK’yı yükler. Uygulamanızın Gemfile’ında incelenmiş bir kopyayı `gem 'lunixi-sdk', path: '/tam/yol/lunixi-ruby'` ile kullanabilirsiniz. Bundler Git kaynağı kullanırken denetlenmiş commit’i sabitleyin.

## İstemci

```ruby
require 'lunixi'

lunixi = Lunixi::Client.new(
  base_url: ENV.fetch('LUNIXI_BASE_URL'),
  key_id: ENV.fetch('LUNIXI_KEY_ID'),
  private_key: File.read(ENV.fetch('LUNIXI_PRIVATE_KEY_PATH')),
  timeout: 30, max_retries: 2
)
```

Gateway adresi `https://api-gateway.lunixi.com` şeklinde yalnız HTTPS origin olmalıdır. TEST/LIVE ortamını anahtar belirler. Her üye işyeri bağlantısı için bir istemci oluşturup paylaşın. Özel anahtarı kaynak kontrolünden ve public web dizininden uzak tutun; yalnız public anahtarı Lunixi paneline kaydedin. PKCS#8 PEM, base64 PKCS#8 DER, base64 32 bayt seed ve 64 bayt secret key desteklenir. Anahtar üretimi:

```bash
umask 077
openssl genpkey -algorithm ED25519 -out lunixi-private.pem
openssl pkey -in lunixi-private.pem -pubout -out lunixi-public.pem
```

## Ödeme başlatma

Toplamı sunucuda hesaplayın. Çağrıdan **önce** ödeme denemesine bir UUID idempotency anahtarı kaydedin. Zaman aşımı ve yeniden başlatma sonrası aynı denemede aynı anahtarı kullanın.

```ruby
result = lunixi.payments.create_intent(
  { amount: "10050", currency: 'TRY', orderId: order.public_id,
    callbackUrl: 'https://merchant.example/payments/return',
    basketItems: [{ id: 'urun-1', name: 'Product', itemType: 'PHYSICAL', price: "10050" }] },
  idempotency_key: order.persisted_payment_attempt_key
)
intent_id = result.fetch('data').fetch('paymentId')
checkout_token = result.fetch('data').fetch('token')
```

`"10050"`, 100,50 TRY’nin kuruş karşılığıdır. Tutarlar pozitif, kanonik alt birim string olmalı ve işaretli 64 bit fiat aralığında kalmalıdır; sayısal değerler kabul edilmez. Eski kök `price`/`paidPrice` alanları null olsa bile reddedilir. Sepet toplamı ve split bacak toplamı ana tutarla aynı olmalıdır. Intent’te `installment` gönderilmez; taksiti ödeme formu seçtirir. `preauth: true` ile provizyon alınabilir; capture ayrı işlem ve anahtarla yapılır.

Varsayılan form mağaza içinde açılır; isteğe bağlı yönlendirme yalnız doğrulanmış backend `paymentPageUrl` adresini kullanır. Token ve adres şifrelenir; iki mod aynı Lunixi form ayarlarını paylaşır. PAN/CVV toplamayın.

HTTP 2xx, token, dönüş sayfası veya devam eden split durumu tahsilat kanıtı değildir. Doğrulanmış webhook ve sunucudan durum sorgusunda intent, sipariş, para birimi, toplam ve nihai durum uyuşmadan siparişi ödenmiş saymayın. Rails örneği sabit toplamlı tek intent’i gösterir; split tahsilat, müşteriye yansıtılan sigorta veya ek ücret açmadan önce mutabakat muhasebesini genişletin.

## API kapsamı

| İşlem | API |
| --- | --- |
| Intent oluşturma | `payments.create_intent(body, idempotency_key:)` |
| Ödeme okuma/listeleme | `payments.get(id)`, `payments.list(**filters)` |
| Açık yöntemler | `payments.methods(payment_method: nil)` |
| Capture | `payments.capture(id, idempotency_key:)` |
| Tam/kısmi iade | `payments.refund(id, idempotency_key:, reason: nil)` |
| Provizyon iptali | `payments.void(id, idempotency_key:)` |
| Çoklu ödeme | `payments.split(body, idempotency_key:)` |
| Split durum/iade | `payments.get_split(id)`, `payments.refund_split(id, amount:, idempotency_key:, reason: nil)` |
| Fraud | `fraud.evaluate(body)`, `fraud.record_event(body, idempotency_key:)` |
| Diğer dokümante uçlar | `request(method, path, body: nil, query: {}, idempotency_key: nil, signed: true, binary: false)` |

Capture/iade için `amount:` anahtarını göndermemek, gateway’in kalan tutarı kullanmasını ister; açık `amount: nil` reddedilir. `"0"`, `false`, sayısal değerler ve kanonik olmayan string tutar reddedilir. Her capture/iade/iptal için ayrı ve kalıcı işlem anahtarı gerekir. Yanıt zarfı korunur. Payment, fraud ve webhook yardımcıları açıktır; diğer servisler dokümante şema ile imzalı transport üzerinden çağrılır. Bu sürüm PHP SDK’sındaki tüm servisler için ayrı tipli istemci sunduğunu iddia etmez.

## Webhook güvenliği

```ruby
verifier = Lunixi::WebhookVerifier.new(
  secret: ENV.fetch('LUNIXI_WEBHOOK_SECRET'), previous_secrets: []
)
verifier.process(raw_request_bytes, signature_headers, store: durable_transactional_store) do |event|
  # Sunucu sorgusuyla doğrulayın; sipariş değişikliğini aynı transaction’da yapın.
end
```

JSON parse işleminden önce **özgün baytları** alın. v2 HMAC-SHA256 imzası `eventId.timestamp.rawBody` üzerinde constant-time karşılaştırılır. Geçmiş/gelecek timestamp toleransı varsayılan 300 saniyedir. En fazla iki önceki secret ile rotasyon desteklenir; yinelenmiş JSON anahtarları ve tutarsız olay kimliği/tipi reddedilir.

Store, `process_once(id:, digest:) { … }` uygular: benzersiz olay kaydı ile sipariş değişikliği **aynı veritabanı transaction’ında** commit olur. Aynı olay `:duplicate`, yeni olay `:processed` döndürür. Aynı kimliğin farklı gövdesi `Lunixi::ReplayConflict` üretir. İşleyici hata verirse olay kaydı geri alınır; yeniden teslim işlenebilir. Bellek içi set yeterli değildir. [RailsReplayStore](samples/rails/app/services/rails_replay_store.rb) gerçek SQLite/veritabanı örneğidir.

## Hatalar ve tekrar deneme

`Lunixi::Error` taban sınıftır. `ConfigurationError`, `SignatureError`, `TransportError`, `RedirectError`, `WebhookError`/`ReplayConflict`, `ApiError`, `AuthenticationError`, `ValidationError` ve `RateLimitError` ayrıştırılır. API hatası yalnız `status`, güvenli `code`, `request_id` ve `retry_after` sunar; gövde, özel anahtar ve karşı tarafın hata metni eklenmez.

GET/HEAD ve anahtarlı işlemler ağ hatası veya 429/502/503/504 için varsayılan 2, en çok 3 kez denenebilir. Aynı gövde/anahtar korunur; her çağrı yeni nonce/imza alır. Güvenli çağrı 401 alırsa token bir kez yenilenir. Anahtarsız mutation otomatik tekrarlanmaz. Belirsiz ağ sonucunda yeni anahtarla tekrar tahsilat başlatmayın; özgün işlemi sorgulayın.

TLS sertifika/hostname doğrulaması zorunludur; yönlendirmeler ve path/credential enjeksiyonu reddedilir. İstek 1 MiB, yanıt 8 MiB ile sınırlıdır. `transport:`, `clock:`, `sleeper:` testlerde enjekte edilebilir; transport `Lunixi::Response` döndürür. `ca_file:` ile güvenilen CA verilebilir; TLS doğrulaması kapatılamaz. Ortam proxy kimlik bilgileri otomatik taşınmaz.

## Rails ve kontroller

Çalıştırma, ortam değişkenleri ve migration için [Rails rehberi](samples/rails/README.md). Örnek; CSRF, demo kimlik doğrulama, şifreli token, kalıcı idempotency, imzalı webhook ve atomik dedupe içerir; tamamlanmış mağaza veya çok kiracılı yetkilendirme sistemi değildir.

```bash
bundle exec rake test
bundle exec rake rails:test
bundle exec rubocop
bundle exec bundle-audit check --update
bundle exec brakeman --force --rails8 --path samples/rails --no-pager
gem build lunixi-sdk.gemspec
```

Testler gerçek para taşımaz. RFC 8032 ve ortak webhook vektörleri, bozulmuş imza, replay/rotasyon, tutar doğruluğu, eşzamanlı token, aynı anahtarla retry ve gerçek yerel TLS sertifika/hostname/yönlendirme/boyut kontrolleri kapsanır. JSON uyumu bağımsız Node.js ile karşılaştırılır. Rails testi gerçek SQLite transaction’larını kullanır. Brakeman’da sabit host yönlendirmesi için tek, gerekçeli ve test edilmiş false positive `samples/rails/config/brakeman.ignore` içinde yer alır.

[Güvenlik](SECURITY.md) · [Katkı](CONTRIBUTING.md) · [Değişiklikler](CHANGELOG.md) · [MIT lisansı](LICENSE) · developer@lunixi.com

## Mağaza içi form ve isteğe bağlı yönlendirme

Rails örneğinde varsayılan `LUNIXI_CHECKOUT_MODE=embedded` değeridir. Mevcut Lunixi formu sabit resmi CDN, HTML için kaçırılmış JSON data attribute ve yanıta özgü CSP nonce ile mağaza sayfasında açılır. `Lunixi::Checkout.browser_config(token)` yalnız resmi object/mount yapılandırmasını verir; gateway HTML'i veya merchant secret'ı basılmaz.

İsteğe bağlı yönlendirme için açıkça `LUNIXI_CHECKOUT_MODE=hosted` seçin. `Lunixi::Checkout.payment_page_url(data.fetch('paymentPageUrl'))` backend adresini birebir doğrular: HTTPS `pay.lunixi.com/payment/` ve 16–4096 karakter ASCII opak değer; userinfo, port, sorgu, fragment veya kontrol karakteri kabul edilmez. Bu değer gömülü token'dan farklı olabilir; token'dan URL üretilmez. İki mod aynı açık yöntemleri, çoklu kartı, taksiti ve sigortayı sunar; yönlendirme şart değildir. Sabit toplamlı tek-intent tahsilat sınırlaması korunur.

Rails örneğini yükseltmeden önce `rails db:migrate` çalıştırın. Yeni istek/mod/dönüş adresi/zaman ağdan önce kaydedilir; gövde, token ve backend adresi Active Record Encryption ile şifrelenir. Tekrar aynı gövde/anahtarla gider; 23 saatten eski finansal gönderim durur. Mevcut satırlar eski hosted akışı olarak işaretlenir; bilinmeyen eski istek veya eksik backend adresi origin/anahtar değiştirilmeden ve adres üretilmeden mutabakat bekler. Genel mod değişikliği yeni rezervasyonlara uygulanır; mevcut istek kayıtlı modunu korur. CSRF/demo yetkisi, ham webhook, atomik receipt ve sınırlı 3DS/çoklu kart dönüşü korunur.

Geçmiş 0.1.2 odaklı kontrolü: 24 Rails form/dönüş/URL/CSP güvenlik testi ve 225 assertion, 2 SDK yardımcı testi ve 5 assertion, RuboCop ve Brakeman (belgeli tek strict-URL yönlendirme false positive'i). Önceki tam 0.1.1 sonuçları temel kanıttır; canlı/merchant kabulü ertelenmiştir.

Checkout sayfasının CSP’si form POST’u için yalnız `'self'` ve yapılandırılan gateway origin’ine (varsayılan `https://api-gateway.lunixi.com`) izin verir. Böylece tarayıcı SDK’sının desteklediği cüzdan/sağlayıcı ve eski POST geçişleri korunur. İncelenmiş başka bir sağlayıcı gerekiyorsa yalnız sunucuda `LUNIXI_FORM_ACTION_ORIGINS` tanımlayın: virgülle ayrılmış tam HTTPS origin’leri; boşluk, yol, sondaki slash, kullanıcı bilgisi, sorgu, fragment ve wildcard kabul edilmez. Geçersiz ayar reddedilir; gateway yanıtı veya tarayıcı alanı listeyi genişletemez. Script nonce, frame/connect sınırları ve bilgilendirici dönüş güvenliği korunur.
