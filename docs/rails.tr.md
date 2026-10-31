---
title: Rails
description: Lunixi Ruby SDK için çalıştırılabilir Rails örneği — hosted ödeme, şifreli token, CSRF, kalıcı webhook dedupe ve ödeme mutabakatı.
---


# Rails

[Ruby SDK](/sdks/ruby) kaynak deposundaki `samples/rails`, çalıştırılabilir Rails 8.1 referans uygulamasıdır. Sunucuda hesaplanan tutarla hosted ödeme başlatır; token’ı şifreli saklar, alıcı rotalarını CSRF ve demo kimlik doğrulamayla korur, doğrulanmış webhook receipt’i ile sipariş değişikliğini atomik commit eder.

Örnek **tek üye işyeri ve sabit toplamlı TRY siparişleri** içindir. Ayrı yayımlanmış Rails gem’i veya tamamlanmış mağaza değildir. İmza, token önbelleği, retry ve webhook kriptografisi `lunixi-sdk` içinde kalır.

## Kurulum

Ruby 3.3+, Bundler, Ed25519 destekli OpenSSL ve SQLite gerekir. SDK’nın bağımsız JSON uyum testi Node.js kullanır.

```bash
git clone https://github.com/Lunixi-Payment/lunixi-ruby.git
cd lunixi-ruby
bundle install
```

Gemfile, yerel SDK ile Rails, Puma ve SQLite bağımlılıklarını kurar. `lunixi-sdk` için RubyGems yayını varsayılmaz. [Örnek kaynak kod](https://github.com/Lunixi-Payment/lunixi-ruby/tree/main/samples/rails).

## Secret ayarları

Başlamadan önce değişkenleri shell veya secret manager üzerinden dışa aktarın. Uygulama dotenv’i otomatik yüklemez; depodaki `samples/rails/.env.example` kontrol listesi olarak kullanılabilir.

| Değişken | Amaç |
| --- | --- |
| `LUNIXI_BASE_URL` | HTTPS gateway origin; normalde `https://api-gateway.lunixi.com` |
| `LUNIXI_KEY_ID` | Kayıtlı TEST/LIVE üye işyeri key id |
| `LUNIXI_MERCHANT_ID` | Doğrulanmış ödeme yanıtıyla birebir eşleşmesi gereken üye işyeri UUID değeri |
| `LUNIXI_PRIVATE_KEY_PATH` | Public web dizini dışındaki özel Ed25519 anahtarı |
| `LUNIXI_WEBHOOK_SECRET` | Kayıtlı webhook bağlantısına ait secret |
| `PUBLIC_ORIGIN` | Bu Rails uygulamasının public HTTPS origin’i; path içermez |
| `DEMO_USERNAME`, `DEMO_PASSWORD` | Demo HTTP Basic; parola en az 16 bayt |
| `SECRET_KEY_BASE` | Kalıcı Rails session secret |
| `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` | Kalıcı ana şifreleme anahtarı |
| `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` | Bağımsız deterministik şifreleme anahtarı |
| `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` | Bağımsız türetme salt’ı |

Session secret için yerelde `ruby -rsecurerandom -e 'puts SecureRandom.hex(64)'` çalıştırın. Şifreleme ayarları için üç bağımsız, rastgele 32 bayt değer daha üretin. Güvenle saklayın ve yeniden başlatmada koruyun. Rails anahtar rotasyonunu planlamadan anahtarları değiştirmeyin; eski anahtarı kaybetmek kayıtlı token’ları okunamaz yapar.

Yerel HTTPS tüneli `PUBLIC_ORIGIN` sağlayabilir. Bu origin dönüş URL’si ve izin verilen host için kullanılır; uygulamadan önce ayarlanmalıdır. Geliştirme sunucusunu kimlik doğrulama olmadan public açmayın.

## Ödeme başlatma

```bash
cd samples/rails
bundle exec rails db:migrate db:seed
bundle exec rails server -b 127.0.0.1
```

`http://localhost:3000/orders/00000000-0000-4000-8000-000000000001` adresini açın, demo bilgileriyle giriş yapıp ödeme butonuna basın. Sentetik başlangıç siparişi **100,50 TRY**’dir. Türkçe arayüz için `?locale=tr` ekleyin.

Checkout POST’u CSRF token ister; tutar/para birimini veritabanından okur. Gateway çağrısından önce siparişe UUID `checkout_key` kaydedilir. Aynı anahtarla intent oluşturulur, `intent_id` saklanır ve `checkout_token` Active Record Encryption ile şifrelenir. Ardından sabit `pay.lunixi.com` host’una 303 yönlendirmesi yapılır. Yeni ve kayıtlı token’lar ASCII allowlist ile doğrulanır; tarayıcı veya gateway başka host/protokol veremez.

Ağ hatasında sipariş pending kalır, işlem anahtarı korunur. Checkout tekrarında aynı anahtar kullanılır. Kayıtlı token yeniden kullanılır; belirsiz deneme silinip sessizce yeni tahsilat açılmaz. Süresi dolmuş veya sonucu bilinmeyen deneme mutabakat gerektirir.

Lunixi formu, üye işyerine açık yöntemleri ve uygun alternatif/çoklu kart akışlarını sunar. Uygulama PAN/CVV işlemez.

## Webhook kaydı

Lunixi panelinde aşağıdaki URL’yi kaydedip eşleşen webhook secret’ını ayarlayın:

```text
https://<public-hostunuz>/webhooks/lunixi
```

Dokümante ödeme olaylarına abone olun. Dış çağrı alan `WebhooksController < ActionController::API`, özgün `request.raw_post` baytlarını kullanır ve tarayıcı session’ına bağlı değildir. Bu ayrı uç dış istek alır; alıcı rotalarında CSRF ve kimlik doğrulama korunur.

SDK v2 imza, zaman, olay kimliği/tipi ve rotasyonu doğrular. `RailsReplayStore`, benzersiz `(connection_id, event_id)` constraint’i olan receipt’i sipariş değişikliğiyle **aynı veritabanı transaction’ına** yazar. Aynı olay ikinci kez 200 döner ve sipariş yeniden işlenmez. Aynı kimliğin farklı baytları 400 alır. İşleyici veya sunucu ödeme sorgusu hatası receipt’i geri alır ve 503 döndürür; tekrar teslim kurtarabilir.

## Tahsilat doğrulama

`WebhookProcessor`, `payment.captured` olayını yalnız kayıtlı sipariş/intent ile eşleştirir. Yetkili `payments.get(intent_id)` çağrısında şunları arar:

- nihai durum `CAPTURED`;
- aynı kalıcı sipariş referansı ve intent;
- aynı para birimi;
- siparişin tam sayı tutarıyla birebir eşleşme.

Bu koşullarla sipariş `paid` olur. Başarısız, yalnız provizyon alınmış, bilinmeyen veya tutarsız sonuç pending kalır. Diğer abone olunan olaylar tahsilat varsayılmadan kaydedilir. Tarayıcı dönüşü yalnız kayıtlı sipariş sayfasına gider; istemcinin `status` / `paid` parametreleri dikkate alınmaz.

> 
SDK split, capture ve iade çağrılarını destekler. Bu örnek sabit toplamlı tek-intent TRY siparişi tamamlar. Split toplam tahsilat, kısmi teslim, müşteriye yansıtılan sigorta ve ek ücret açmadan önce açık muhasebe/mutabakat mantığı ekleyin. Eşleşmeyen tutar güvenli biçimde pending kalır.


## Kendi uygulamanıza uyarlama

Demo HTTP Basic yerine müşteri/session/tenant ve sipariş sahipliği kontrollerinizi bağlayın. Sunucu toplamını, işlem başına kalıcı anahtarı ve atomik receipt/sipariş transaction’ını koruyun. Eksik webhook ve belirsiz sonuçlar için kalıcı mutabakat işi ekleyin; aynı korelasyon verisini kullanın.

Örnek SQLite ile test edilir. Başka üretim veritabanında ilgili Rails adapter’ını kurup transaction/eşzamanlılık kontrollerini yineleyin. Transaction içindeki uzun gateway sorgusu örneği sade tutar ama kapasiteyi sınırlar. Üretimde outbox/state machine ile kısa transaction kullanılabilir; olay kaydı ve iş değişikliğinin atomikliği korunmalıdır.

Yerel/test dışındaki ortamlarda HTTPS zorunludur. Rails yönlendirme adresine checkout token’ını yazabildiği için info istek logları kapalıdır. Ham ödeme/webhook gövdesi veya secret loglamayın. Kalıcı session/şifreleme anahtarları ve kalıcı veritabanı kullanın.

## Test ve güvenlik

Depo kökünde:

```bash
bundle exec rake test rails:test
bundle exec rubocop
bundle exec bundle-audit check --update
bundle exec brakeman --force --rails8 --path samples/rails --no-pager
gem build lunixi-sdk.gemspec
```

Rails testleri sentetik gateway yanıtları ve gerçek SQLite kullanır; anahtar veya para hareketi gerektirmez. Kimlik doğrulama/CSRF, şifreli token, kalıcı anahtar, yönlendirme saldırısı, tarayıcı dönüşüne güvenmeme, imza, dedupe, yanlış tutar/sipariş ve rollback/yeniden teslim kapsanır. Brakeman’ın sabit host yönlendirmesine ait tek düşük güvenli false positive’i, kesin fingerprint ve saldırı testleriyle `samples/rails/config/brakeman.ignore` içinde gerekçelendirilmiştir. Genel bir güvenlik kategorisi kapatılmaz.

Canlıya geçmeden yetkili TEST üye işyeriyle uçtan uca ödeme, webhook ve iade kabul testi yapın. [Örnek README](https://github.com/Lunixi-Payment/lunixi-ruby/tree/main/samples/rails) ve [güvenlik politikası](https://github.com/Lunixi-Payment/lunixi-ruby/blob/main/SECURITY.md).
