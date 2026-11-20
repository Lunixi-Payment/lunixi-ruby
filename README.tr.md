<p align="center"><img src=".github/assets/lunixi-logo.svg" width="300" alt="Lunixi"></p>

# Lunixi Ruby SDK

[English](README.md) · [Türkçe](README.tr.md) · [Dokümantasyon](https://docs.lunixi.com/tr/sdks/ruby) · [Rails örneği](samples/rails)

Lunixi ödemeleri, fraud işlemleri ve imzalı gateway çağrıları için sunucu tarafı Ruby SDK’sı. Ed25519 imzasını OpenSSL ile üretir; token’ı eşzamanlı istekler arasında önbelleğe alır, tutarları kanonik alt birim string olarak korur ve güvenli tekrar denemelerde aynı idempotency anahtarını kullanır. v2 webhook doğrulaması özgün istek baytları üzerinden yapılır.

## Gereksinimler ve kurulum

Ruby **3.3+**, **Ed25519** destekli OpenSSL ve Bundler gerekir. Çalıştırılabilir örnek **Rails 8.1** ve SQLite kullanır; ana gem Rails’e bağımlı değildir.

[RubyGems üzerinde yayımlanan 1.0.1 sürümünü](https://rubygems.org/gems/lunixi-sdk/versions/1.0.1) `Gemfile` dosyanıza ekleyip `bundle install` çalıştırın. [Para sözleşmesi geçişini](MIGRATION-1.0.md) uygulayın:

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
    # Her ödemenin istediği sipariş bilgileri (ödeme sayfanızdan alın, yer tutucu kullanmayın).
    # Intent'te buyer.ip gönderilmeyebilir: Lunixi formu IP'yi alıcının tarayıcısından alır.
    buyer: { name: 'Ada', surname: 'Yilmaz', identityNumber: '11111111111', email: 'ada@example.com',
             gsmNumber: '+905350000000', city: 'Istanbul', country: 'Turkey', zipCode: '34000' },
    billingAddress: { contactName: 'Ada Yilmaz', address: 'Example Street 1', city: 'Istanbul', country: 'Turkey', zipCode: '34000' },
    shippingAddress: { contactName: 'Ada Yilmaz', address: 'Example Street 1', city: 'Istanbul', country: 'Turkey', zipCode: '34000' },
    basketItems: [{ id: 'urun-1', name: 'Product', category1: 'Electronics', itemType: 'PHYSICAL', price: "10050" }],
    enabledInstallments: [1, 2, 3] }, # isteğe bağlı: en fazla 3 taksit
  idempotency_key: order.persisted_payment_attempt_key
)
intent_id = result.fetch('data').fetch('paymentId')
checkout_token = result.fetch('data').fetch('token')
```

Her ödeme gövdesi sipariş bilgilerini taşır (`Lunixi::OrderDetails`): `buyer` (`name`, `surname`, `identityNumber` — T.C. kimlik veya pasaport numarası, `email` — ASCII, `gsmNumber`, `city`, `country`, `zipCode`, `ip` — alıcının tarayıcı IP'si), `billingAddress` (`contactName`, `address`, `city`, `country`, `zipCode`) ve en az bir `basketItems` satırı (`id`, `name`, `category1`, `itemType`, `price`; fiyatların toplamı tutara eşittir); `PHYSICAL` bir satır `shippingAddress` de ister. `create_intent`, `create_marketplace_intent` ve `marketplace.create_checkout_intent` çağrılarında `ip` gönderilmeyebilir (`Lunixi::CHECKOUT_INTENT_BUYER_OPTIONAL_FIELDS`): Lunixi formu IP'yi alıcının tarayıcısından alır. `create_intent`, `create_marketplace_intent`, `direct_method_payment`, `split`, pazaryeri intent'leri ve kart tahsilatları, `store_card` (yalnız alıcı ve fatura adresi) ve `wallet.topups.start_card` (alıcı ve fatura adresi, `shippingAddress` isteğe bağlı) eksik alanların yollarını sayan bir `ConfigurationError` ile göndermeden önce durur; `Lunixi::OrderDetails.missing(body)` aynı listeyi döndürür (`buyer.email`, `basketItems.0.category1`, `shippingAddress`). Alan listeleri `Lunixi::ORDER_DETAILS_REQUIRED_FIELDS`, `Lunixi::BUYER_REQUIRED_FIELDS`, `Lunixi::ADDRESS_REQUIRED_FIELDS` ve `Lunixi::BASKET_ITEM_REQUIRED_FIELDS` sabitlerindedir. Gateway eksik alanı 400 `payment.order.field_required`, geçersiz alanı `payment.order.field_invalid` ile yanıtlar (`Lunixi::OrderFieldErrorCode`, `Lunixi::OrderFieldReason`).

`"10050"`, 100,50 TRY’nin kuruş karşılığıdır. Tutarlar pozitif, kanonik alt birim string olmalı ve işaretli 64 bit fiat aralığında kalmalıdır; sayısal değerler kabul edilmez. Eski kök `price`/`paidPrice` alanları null olsa bile reddedilir. Sepet toplamı ve split bacak toplamı ana tutarla aynı olmalıdır. Her `basketItems` satırı isteğe bağlı `productCategory` alanını taşıyabilir: Lunixi ürün kategorisi kodu (ör. `'MOBILE_PHONE'`); yasal taksit sınırı olan ödeme yöntemleri (ör. alışveriş kredisi) ve diğer platform özellikleri tarafından kullanılır. Alanı göndermezseniz mevcut davranış korunur; gateway bilinmeyen kodu 400 ile reddeder. Kodlar `Lunixi::ProductCategory` sabitleri olarak hazırdır (`Lunixi::ProductCategory::MOBILE_PHONE`, 40 kodun tamamı `Lunixi::ProductCategory::ALL` içinde); liste yalnız sona ekleme ile büyüdüğünden değer düz string olarak kalır ve SDK göndermeden önce denetlemez. Intent’te `installment` gönderilmez; taksiti ödeme formu seçtirir. İsteğe bağlı `enabledInstallments` listesi, bir ödeme için formun sunacağı taksit sayılarını yalnızca daraltır (`[1]` = yalnız tek çekim); form, panel ayarlarınızın, kartın ve platform üst sınırının da izin verdiği sayıları gösterir. Kısıt istemiyorsanız alanı göndermeyin. Liste 1–36 arası, tekrarsız ve 1'i içeren tamsayılardan oluşmalıdır; başka bir liste (boş liste dahil) göndermeden önce `ConfigurationError` oluşturur ve liste artan sırada gönderilir. `preauth: true` ile provizyon alınabilir; capture ayrı işlem ve anahtarla yapılır.

Varsayılan form mağaza içinde açılır; isteğe bağlı yönlendirme yalnız doğrulanmış backend `paymentPageUrl` adresini kullanır. Token ve adres şifrelenir; iki mod aynı Lunixi form ayarlarını paylaşır. PAN/CVV toplamayın.

HTTP 2xx, token, dönüş sayfası veya devam eden split durumu tahsilat kanıtı değildir. Doğrulanmış webhook ve sunucudan durum sorgusunda intent, sipariş, para birimi, toplam ve nihai durum uyuşmadan siparişi ödenmiş saymayın. Rails örneği sabit toplamlı tek intent’i gösterir; split tahsilat, müşteriye yansıtılan sigorta veya ek ücret açmadan önce mutabakat muhasebesini genişletin.

## API kapsamı

| İşlem | API |
| --- | --- |
| Intent oluşturma | `payments.create_intent(body, idempotency_key:)` |
| Ödeme okuma/listeleme | `payments.get(id)`, `payments.list(**filters)` |
| Açık yöntemler | `payments.methods(payment_method: nil)`, takma ad `payments.list_payment_methods(payment_method: nil)` |
| Herhangi bir yöntemle ödeme | `payments.direct_method_payment(body_or_request, idempotency_key:)`, `Lunixi::DirectMethodPaymentRequest` |
| Ödeme adımı | `payments.confirm_payment_action(payment_id, action_id, input)`, `payments.resend_payment_action(payment_id, action_id)` |
| Senetler | `payments.get_promissory_notes(id)`, `payments.cancel_promissory_notes(id, serial_numbers: nil, idempotency_key: nil)`, `payments.download_promissory_note_document(id, locale: nil)` |
| Para Transferi istisnaları | `payments.list_bank_transfer_exceptions(environment: nil, status: nil, limit: nil)`, `payments.accept_bank_transfer_exception(id)`, `payments.mark_bank_transfer_exception_refunded(id)` |
| Adres sözlüğü | `reference.list_provinces`, `reference.list_districts(province_code)`, `reference.list_neighborhoods(district_code)` |
| Capture | `payments.capture(id, idempotency_key:)` |
| Tam/kısmi iade | `payments.refund(id, idempotency_key:, reason: nil)` |
| Provizyon iptali | `payments.void(id, idempotency_key:)` |
| Çoklu ödeme | `payments.split(body, idempotency_key:)` |
| Split durum/liste/iade | `payments.get_split(id)`, `payments.list_splits(**filters)`, `payments.refund_split(id, amount:, idempotency_key:, reason: nil)` |
| Pazaryeri intent'i | `payments.create_marketplace_intent(body, idempotency_key:)` |
| BIN ve taksitler | `payments.bin_info(bin_or_pan)`, `payments.installment_options(body_or_request)`, `payments.card_taxonomy`, `Lunixi::InstallmentOptionsRequest` |
| Saklı kartlar | `payments.store_card(body_or_request, idempotency_key:)`, `payments.list_stored_cards(card_user_key)`, `payments.get_stored_card(token)`, `payments.deactivate_stored_card(token, idempotency_key:)`, `Lunixi::StoreCardRequest` |
| Ödeme analizleri | `payments.failover_recovery_analytics(**filters)`, `payments.provider_credential_analytics(credential_id, **filters)` |
| Ödeme linkleri | `payment_links.create`, `list`, `get`, `update`, `pause`, `resume`, `deactivate`, `action`, `send_link`, `qr`, `list_attempts`, `list_payments` |
| Ödeme linki görseli | `payment_links.create_image_upload`, `payment_links.confirm_image_upload(asset_id)`, `payment_links.upload_image(file_name:, content_type:, content:)` |
| Fraud kararı | `fraud.evaluate(body)` |
| Fraud karar kaydı | `fraud.decisions.list(**filters)`, `fraud.decisions.get(trace_id)`, `fraud.decisions.latest_for_payment(payment_id)` |
| Fraud işlem olayı | `fraud.record_event(body, idempotency_key:)` (`fraud.events.record` ile aynı), `fraud.events.record_batch(events, idempotency_key:)` |
| Fiziki POS ödemeleri | `physical_pos.create_payment(request, idempotency_key:)`, `create_reversal(payment_id, request, idempotency_key:)`, `cancel_payment`, `get_payment`, `list_payments`, `list_transactions`, `get_transaction`, `list_ambiguous_payments` |
| Fiziki POS raporları ve gün sonu | `physical_pos.get_sales_summary`, `get_tax_summary`, `list_settlements`, `start_settlement(device_id, idempotency_key: nil)`, `list_settlement_runs`, `get_settlement_run` |
| Fiziki POS yönetimi | `physical_pos_management` mağazalar, kasalar, terminaller (banka ve sağlayıcı satırları, cihaz bağlantıları), cihazlar ve kimlik anahtarları, gün sonu politikaları, katalog ve genel görünüm |
| Cüzdan | `wallet.ping`, `wallet.end_users`, `wallets`, `deposits`, `corporate`, `fees`, `transfers`, `withdrawals`, `operations`, `topups`, `payments`, `qr`, `bulk_payouts` |
| Banka hesapları | `bank_connect.list_banks`, `list_connections`, `get_connection`, `list_accounts`, `get_account`, `request_sync`, `list_balances`, `list_transactions`, `get_transaction` |
| Banka transferleri ve döviz | `bank_connect.transfers.list_purposes`, `create(request, idempotency_key: nil)`, `list`, `get`; `bank_connect.fx.list_rates`, `create_quote`, `create_order(request, idempotency_key: nil)`, `list_orders`, `get_order` |
| Yaptırım taraması | `sanction.screen_name`, `screen_wallet`, `screen_account`, `screen_transaction`, `screen_public_procurement_ban`, `screen_adverse_media`, izleme, varlık istihbaratı, `list_blacklist_entries`, `Lunixi::Sanction.clear_screening?(result)` |
| Sigorta | `insurance.list_products`, `search_products`, `create_quote`, `create_order`, `bind_payment`, `confirm_payment`, `issue_policy`, `cancel_order`, `refund_premium`, poliçe dosyaları, mutabakat, potansiyel müşteriler |
| Abonelik | `subscriptions.create(request, idempotency_key:)`, `get`, `list`, `cancel`, `pause`, `resume`, `change_plan`, `audit_logs`; alt istemciler `plans`, `customers`, `cards`, `invoices`, `portal`, `products`, `features`, `addons`, `usage` |
| KYC / KYB / kanıt | `kyc.create_session`, `get_session`, `list_sessions`, `set_jurisdiction`, `set_primary_document`, `upload_document`, `timeline`, `submit`, `manual_review`, `evidence_request`, üye işyeri politikası, webhook kuyruğu, silme talepleri |
| Kimlik sinyalleri | `identity.analyze_sync`, `analyze`, `account_links`, `get_session`, `related_sessions`, `timeline`, `top_sources`, `list_sessions` |
| Pazaryeri | `marketplace.create_checkout_intent`, `charge_marketplace_card2d`, `charge_marketplace_card3d`, alt bayiler, komisyonlar, hakediş ödemeleri, denetim kaydı |
| Diğer dokümante uçlar | `request(method, path, body: nil, query: {}, idempotency_key: nil, signed: true, binary: false, accept: 'application/json', max_retries: nil)` |

Capture/iade için `amount:` anahtarını göndermemek, gateway’in kalan tutarı kullanmasını ister; açık `amount: nil` reddedilir. `"0"`, `false`, sayısal değerler ve kanonik olmayan string tutar reddedilir. Her capture/iade/iptal için ayrı ve kalıcı işlem anahtarı gerekir. Yanıt zarfı korunur. Ödemeler, fraud, ödeme linkleri, fiziki POS, cüzdan, banka hesapları, yaptırım taraması, sigorta, abonelik, KYC, kimlik sinyalleri ve pazaryeri kendi istemcilerine sahiptir; diğer ürünler yayımlanan gateway şemasıyla imzalı transport üzerinden çağrılır.

```ruby
# Advanced transport: a documented existing endpoint, not a second HTTP stack.
banks = lunixi.request('GET', '/api/v1/bank-connect/banks', query: { limit: 20 })
```

## Ödeme yöntemleri

`payments.list_payment_methods` (imzalı) hesabınıza açık yöntemleri döndürür. Her yöntem `blockName`, `providerSelection` (`Lunixi::ProviderSelection`), `providerSelectionMode` (`Lunixi::ProviderSelectionMode`) değerlerini ve yöntem bloğunda gönderilecek `inputFields` alanlarıyla sağlayıcılarını taşır. Sağlayıcı kodunu her zaman bu yanıttan okuyun; kodda sabitlemeyin. `payment_method:` listeyi tek bir koda daraltır (`Lunixi::PaymentMethod`); `QR`, `QR_CODE` olarak gönderilir ve hatalı kod göndermeden önce `ConfigurationError` oluşturur.

`payments.direct_method_payment` herhangi bir yöntemle ödemeyi sunucunuzdan başlatır (`POST /api/v1/payments/direct/payment`, imzalı). `idempotency_key:` zorunludur; aynı ödemeyi yeniden denerken aynı anahtarı kullanın. Gövdeyi `Lunixi::DirectMethodPaymentRequest` ile kurun ya da ham bir Hash verin; ikisi de göndermeden önce denetlenir: yalnız bilinen alanlar (`Lunixi::DIRECT_METHOD_PAYMENT_FIELDS`), tam olarak seçilen yöntemin bloğu (`Lunixi::METHOD_BLOCK_FIELDS`, camelCase yöntem kodu), kart alanları (`Lunixi::CARD_ONLY_FIELDS`) yalnız `CARD` ile, blok yapısı (en fazla 32 alan; en fazla 1024 karakterlik string'ler, sayılar, boolean'lar, `ADDRESS` nesneleri ve en fazla 10 nesnelik `GROUP` listeleri), senet planı ve `SHOPPING_LOAN` için 1–100 sepet kalemi.

```ruby
request = Lunixi::DirectMethodPaymentRequest.new('10000', 'TRY', order.reference)
                                            .with_method_fields(Lunixi::PaymentMethod::MOBILE_BILLING, provider_code,
                                                                gsmNumber: '+905321234567')
                                            .with_buyer(buyer).with_billing_address(billing_address) # buyer burada ip içerir
                                            .with_basket_items(basket_items)
result = lunixi.payments.direct_method_payment(request, idempotency_key: order.payment_operation_key)

action = result.dig('data', 'action')
if action && action['type'] == Lunixi::PaymentActionType::OTP
  lunixi.payments.confirm_payment_action(result.dig('data', 'paymentId'), action['id'], otp: code_from_buyer)
end
```

`confirm_payment_action` yalnız `otp` (rakamlar), `consentAccepted` (boolean) ve `fields` (bir `INPUT` adımının istediği değerler) gönderir; checkout token alanları reddedilir. `resend_payment_action` yeni bir tek kullanımlık kod gönderir; yeni `data.action.id` ile onaylayın. Kartlı ödeme `with_card(card_fields)`, `with_installment(count, quote_token)` ve `with_force3d(true)` kullanır.

### Senetle Ödeme

Bir `PROMISSORY_NOTE` ödemesi planını taşır: ya `with_promissory_note_schedule([{ amount: '5000', dueDate: '2027-01-15' }, …])` (1–24 satır, toplamı `amount` değerine eşit pozitif küçük birim tutarlar, sıralı `YYYY-MM-DD` tarihler) ya da `with_promissory_note_count(3)`; ikisi birden olmaz. `get_promissory_notes(payment_id)` senetleri listeler (`Lunixi::PromissoryNoteStatus`), `cancel_promissory_notes(payment_id, serial_numbers: nil)` verilen senetleri ya da açık senetlerin tümünü iptal eder (`Lunixi::PromissoryNoteCancelResult`, `Lunixi::PromissoryNoteCancelErrorCode`), `download_promissory_note_document(payment_id, locale: 'tr-TR')` ise yazdırılabilir PDF'i dondurulmuş binary String olarak döndürür. Senet değişiklikleri `Lunixi::PromissoryNoteEvents` webhook'larıyla gelir. `reference.list_provinces`, `list_districts` ve `list_neighborhoods` bir `ADDRESS` alanının adres kodlarını döndürür.

### Para Transferi

`BANK_TRANSFER` ödemesi sağlayıcı kodu almaz: alıcının bankasını `with_method_fields(Lunixi::PaymentMethod::BANK_TRANSFER, nil, bankCode: '0062')` ile gönderin; listede olmayan bir bankadan EFT/FAST için `Lunixi::BANK_TRANSFER_OTHER_BANKS_CODE` (`'9999'`) kullanın. Yanıt, alıcıya gösterilecek transfer talimatını taşıyan bir `DISPLAY` adımı içerir:

```ruby
instruction = Lunixi::BankTransferInstruction.from_response(result)
# instruction.iban, instruction.holder_name, instruction.amount_minor, instruction.payment_code, instruction.expires_at
```

Yanıtta `DISPLAY` transfer talimatı yoksa `from_response` nil döndürür. Geç, eksik ve fazla gelen transferler istisnaya dönüşür: `list_bank_transfer_exceptions(environment: 'LIVE', status: 'PENDING_DECISION', limit: 50)`, `accept_bank_transfer_exception(id)` ve `mark_bank_transfer_exception_refunded(id)` (`Lunixi::PaymentBankTransferExceptionKind`, `Lunixi::PaymentBankTransferExceptionStatus`, webhook adları `Lunixi::PaymentBankTransferEvents` içinde).

### Parçalı ödeme

Çoklu ödeme gövdesi (`Lunixi::SPLIT_PAYMENT_FIELDS`) parçalarla birlikte sipariş bilgilerini taşır: `buyer`, `billingAddress`, `basketItems` (toplamı `totalAmount`) ve `PHYSICAL` bir satır için `shippingAddress`. Kart dışı bir parça `Lunixi::SPLIT_LEG_BLOCK_FIELDS` alanlarından (`mobileBilling`, `wallet`, `promissoryNote`) yalnız birini taşır; yemek kartı, açık bankacılık, alışveriş kredisi ve Para Transferi parça olamaz ve göndermeden önce reddedilir. `list_splits(status: 'COMPLETED', limit: 25)` parçalı ödemeleri listeler (`Lunixi::LIST_SPLIT_PAYMENTS_FILTERS`). Webhook adları `Lunixi::SplitPaymentEvents` içindedir; parça olaylarını da almak için uç noktanın olay türlerine `Lunixi::SPLIT_LEG_EVENTS_SUBSCRIPTION` ekleyin.

### BIN, taksitler ve saklı kartlar

`payments.bin_info('45438800')` bir BIN'in veya kart numarası önekinin (6–19 hane) kart ve banka bilgilerini döndürür. `payments.installment_options` taksit tablosunu döndürür; BIN ve 1'den büyük `installment` ile birlikte `DirectMethodPaymentRequest#with_installment` için bağlayıcı `quoteToken` değerini de döndürür. `enabledInstallments` alanı `create_intent` kuralını izler. Kart numaraları ve BIN'ler hiçbir hata mesajında veya istek builder'larının `inspect` çıktısında görünmez.

```ruby
options = lunixi.payments.installment_options(
  Lunixi::InstallmentOptionsRequest.new('10000', 'TRY').with_bin_or_pan(bin).with_enabled_installments([1, 2, 3])
)
```

`payments.store_card(Lunixi::StoreCardRequest.new(card, card_user_key, callback_url).with_buyer(buyer).with_billing_address(billing_address), idempotency_key:)` bir kartı doğrular ve saklar (imzalı; alıcı olarak kart sahibi ve fatura adresi zorunludur); `list_stored_cards(card_user_key)` ve `get_stored_card(token)` maskelenmiş kart verisini döndürür, `deactivate_stored_card(token, idempotency_key:)` kartı kaldırır (imzalı). İki yazım da idempotency anahtarı ister.

`payments.create_marketplace_intent` intent gövdesine ek olarak `sellers` (`[{ subDealerId:, amountMinor:, scenario: }]`) ve `multiSellerPolicy` alır. Her `amountMinor` kanonik küçük birim string'idir ve satıcıların toplamı `amount` değerine eşit olmalıdır; başka bir toplam göndermeden önce `ConfigurationError` oluşturur.

## Ödeme linkleri

`client.payment_links` `/api/v1/payments/links` rotalarını kapsar. Okumalar dahil her çağrı imzalıdır; üye işyerini ve TEST/LIVE ortamını imzalayan anahtar belirler. Yanıtlar gateway zarfıdır: bir liste `data.items` ve üst düzey `pageInfo` (`hasMore`, `nextCursor`, `totalCount`) taşır.

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

- `create` yalnız `Lunixi::PAYMENT_LINK_SPEC_FIELDS` alanlarını ve `environment` değerini kabul eder; `update` linkin güncel `rowVersion` değerini ve değişen alanları alır (`nil` bir alanı temizler), `Lunixi::PAYMENT_LINK_IMMUTABLE_FIELDS` alanlarını reddeder. `startsAt`, `expiresAt` veya `eventAt` içindeki bir `Time` ISO 8601 UTC olarak gönderilir.
- `create` ve `send_link` idempotency anahtarı ister; `update`, `pause`, `resume` ve `deactivate` isteğe bağlı anahtar alır.
- `list`, `list_attempts` ve `list_payments` yalnız belgelenmiş filtrelerini kabul eder; bir Array (`state`, `usage`, `amountMode` için) virgüllü liste olarak gönderilir.
- `qr(link_id, format: 'png', size: 512)` görseli dondurulmuş binary String olarak döndürür.

Link görseli üç adımda ya da `upload_image` ile tek çağrıda yüklenir:

```ruby
image = lunixi.payment_links.upload_image(file_name: 'cover.png', content_type: Lunixi::PaymentLinkImageContentType::PNG,
                                          content: File.binread('cover.png'))
asset_id = image.dig('data', 'assetId') # use as imageAssetId
```

`create_image_upload` yükleme hedefini döndürür (`assetId`, `uploadUrl`, `uploadHeaders`, `expiresAt`); baytlar ardından `uploadUrl` adresine PUT ile gönderilir ve `confirm_image_upload(asset_id)` görseli yayımlar. PUT isteği yapılandırılan transport üzerinden doğrudan depolama sunucusuna, yalnız `uploadHeaders` ile gider: erişim token'ını, imza başlıklarını veya idempotency anahtarını asla taşımaz. HTTPS olmayan, `PUT` olmayan veya başlıkları hatalı bir yükleme hedefi hiçbir şey yüklenmeden önce `ApiError` oluşturur. Başarısız PUT yeniden denenmez; depolama durumu ve koduyla `ApiError` oluşturur (örneğin adresin süresi dolduğunda `AccessDenied`); yeni adres için `upload_image` yeniden çağrılabilir. Görseller PNG, JPEG veya WebP (asla SVG değil) ve en fazla 2 MiB olmalıdır.

## Fraud karar kaydı ve toplu olaylar

`fraud.decisions.list(paymentId:, decision:, integrationMode:, productContext:, limit:, cursor:)` kaydedilmiş kararları listeler (`data` sayfadır, `pageInfo.nextCursor` sonraki imleçtir); `fraud.decisions.get(trace_id)` tek bir kararı, `fraud.decisions.latest_for_payment(payment_id)` bir ödemenin son karar Hash'ini ya da nil döndürür. `fraud.events.record_batch(events, idempotency_key:)` en fazla 500 işlem olayını tek bir imzalı JSON dizisi olarak gönderir; toplu kayıt kısmen başarılı olabilir, bu yüzden `data` içindeki olay başına sonuçları okuyun.

## Fiziki POS

`client.physical_pos` kart terminallerinizde ödemeleri başlatır ve izler (`/api/v1/physical-pos`); `client.physical_pos_management` mağazaları, kasaları, mantıksal terminalleri, cihazları ve gün sonu politikasını yönetir. Her çağrı imzalıdır; TEST anahtarı yalnız okuyabilir. Gövde ve filtre anahtarları ağdaki adlardır (String veya Symbol; snake_case de çalışır), tutarlar kanonik küçük birim string'leri, adetler sayıdır.

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

- Ödeme yazımı "kabul edildi" anlamına gelir: sonucu `physical_pos.payment.*` webhook'larıyla veya `get_payment` ile izleyin. `create_payment` ve `create_reversal` idempotency anahtarı ister (8–200 yazdırılabilir ASCII karakter, verildiği gibi gönderilir); `cancel_payment`, `start_settlement` ve anahtarlı yönetim yazımları `nil` verdiğinizde bir UUID üretir ve onu `idempotency_key` olarak döndürür.
- Ödeme yazımı aynı anahtar ve gövdeyle 1 + `max_retries` kez denenir. Yanıt gelmemesi, "başlamadı" demeyen bir 5xx ya da ödeme içermeyen bir 2xx sonucu bilinmez bırakır ve sonraki deneme 4xx almış olsa bile `PhysicalPosOutcomeUnknownError` ile biter. Asla yeni anahtarla yeniden denemeyin: kart iki kez çekilebilir.
- Kart verisi hiçbir zaman gönderilmez; kart cihazda okunur. Herhangi bir derinlikteki kart verisi alanı (`pan`, `cardNumber`, `cvv`, `expiry`, `track2` …) ya da `merchantReference`, kalem adı, vergi grubu veya serbest metin filtresindeki bir kart numarası, hiçbir şey gönderilmeden önce `PhysicalPosCardDataRejectedError` oluşturur; hata alanın adını verir, değerini asla vermez. Diğer bilinmeyen alan veya filtreler `ConfigurationError` oluşturur.
- Listeler `Lunixi::PhysicalPosPage` döndürür (`items`, `has_more`, `next_cursor`, `total_count`); her listenin bütün sayfaları gezen bir `iterate_*` eşi vardır. Güncellemeler ve durum değişiklikleri son okuduğunuz `rowVersion` değerini alır.
- Tipli hatalar: `PhysicalPosVoidAfterSettlementError` (`allowed_operation`, genellikle `REFUND`), `PhysicalPosRateLimitError` (saniye cinsinden `retry_after`), `PhysicalPosCardDataRejectedError` (`field`).

Fiziki POS webhook'ları imza denetiminden geçirilerek okunur, asla onu atlayarak değil:

```ruby
event = Lunixi::PhysicalPosWebhook.parse(raw_request_bytes, signature_headers, ENV.fetch('LUNIXI_WEBHOOK_SECRET'))
case event.category
when Lunixi::PhysicalPosWebhook::CATEGORY_PAYMENT then apply_payment(event.data, event.history_seq, event.cashier)
when Lunixi::PhysicalPosWebhook::CATEGORY_SETTLEMENT then record_end_of_day(event.data) # no history_seq: deduplicate by event.id
end
```

Teslim sırası garanti değildir: `event.id` ile tekilleştirin ve `history_seq` değeri son uyguladığınızdan büyük olmayan ödeme olayını yok sayın. `event.original` bir ters işlemin özgün ödemesini, `event.cashier` cihazın kasiyer oturumunu (yoksa nil) gösterir; `event.device_sale?` doğrudan cihazda yapılan satışı belirtir.

## Cüzdan

`client.wallet` sunucudan sunucuya cüzdan yüzeyidir (`/api/v1/wallet`). Her çağrı imzalıdır; anahtar `WALLET_SERVICE` ürününe ve rotanın cüzdan yetkisine sahip olmalıdır. Gövdeler ve filtreler hiçbir şey gönderilmeden önce `Lunixi::WALLET_ROUTES` ile denetlenir: bilinmeyen alan, eksik zorunlu alan, küçük birim rakam string'i olmayan tutar (`"12550"`; asla `125.5` veya `12550` değil) ya da eksik `Idempotency-Key` `ConfigurationError` oluşturur. Anahtarlar ağdaki adlardır (String veya Symbol; snake_case de çalışır).

```ruby
step = lunixi.wallet.transfers.initiate_w2w(
  { endUserId: end_user_id, sourceWalletAccountId: account_id, destinationWalletNo: wallet_no, amount: '12550', currency: 'TRY' },
  idempotency_key: transfer.initiate_key
)
lunixi.wallet.transfers.complete_w2w(step['operationId'], { endUserId: end_user_id, integrityHash: step['integrityHash'],
                                                            nonce: step['nonce'], otpCode: otp }, idempotency_key: transfer.complete_key)
```

Para iki adımda hareket eder: `initiate_*` limiti ayırır, `complete_*` aynı `integrityHash` ve `nonce` ile kesinleştirir (SDK `operationId` değerini gövdeye koyar). Listeler `Lunixi::ListPage` döndürür (`items`, `next_cursor`, `has_more?`); `iterate` bütün sayfaları gezer. `qr.image` görsel baytlarını döndürür. `end_users.freeze_end_user(end_user_id, ...)` bir son kullanıcıyı dondurur (`Object#freeze` anlamını korusun diye bu adı taşır).

## Banka hesapları, transferler ve döviz

`client.bank_connect` bağlı banka hesaplarınızı, bakiyelerinizi ve hesap hareketlerinizi okur; banka bağlantıları Lunixi panelinden kurulur. Her çağrı imzalıdır ve ortamı anahtar belirler. Filtreler göndermeden önce denetlenir: kümelerindeki değerler, 1–100 arası `limit`, en fazla 100 hesap kimliği, `minAmountMinor` / `maxAmountMinor` için küçük birim string'leri, en fazla 92 gün arayla `bookedFrom` (dahil) / `bookedTo` (hariç) ve yalnız `bookedFrom` ile birlikte `bookedTo`.

```ruby
page = lunixi.bank_connect.list_transactions(accountId: [account_id], bookedFrom: Time.now - 7 * 86_400, direction: 'CREDIT')
transfer = lunixi.bank_connect.transfers.create(
  { accountId: account_id, receiverIban: iban, receiverName: 'Receiver Name', amountMinor: '150075', description: 'Invoice 42' },
  idempotency_key: payout.id # 8–200 printable ASCII; a UUID v4 is generated when nil
)
```

`transfers` ve `fx`, `bank-connect:transfer` kapsamını ve IP izin listesi olan bir anahtarı ister. `transfers.create` ve `fx.create_order` ağ hatasını veya 5xx yanıtını aynı anahtar ve gövdeyle yeniden dener; süreçler arasında güvenle yeniden denemek için kendi anahtarınızı verin (aynı anahtar ve gövde mevcut kaydı `replayed: true` ile döndürür). Yanıt almış bir hata anahtarı `idempotency_key` olarak taşır. `fx.create_quote`, `sourceAmountMinor` / `targetAmountMinor` alanlarından tam olarak birini alır.

## Yaptırım taraması

`client.sanction` isimleri, cüzdanları, hesapları ve işlemleri tarar, sürekli izleme çalıştırır ve varlık istihbaratını okur. Bu çağrılar yalnız erişim token'ını taşır (istek imzası yoktur). Gövdeler ve filtreler, iç içe satırlar ve değer kümeleri (`Lunixi::SanctionRiskDomain`, `SanctionScreenMode`, `SanctionWalletScreenMode`) dahil, göndermeden önce `Lunixi::SANCTION_ROUTES` ile denetlenir.

```ruby
result = lunixi.sanction.screen_name(name: 'Customer Name', riskDomains: [Lunixi::SanctionRiskDomain::SANCTIONS], customerReference: customer.id)
review!(result) unless Lunixi::Sanction.clear_screening?(result)
```

Tarama karar değil eşleşme döndürür. Sonuç yalnız eşleşme veya isabet, engelleyici işaret veya karar yoksa ve kapsam bildiriyorsa `coverageStatus` değeri `COMPLETE` ise temizdir; çalıştırılamayan tarama `ApiError` oluşturur ve hiçbir zaman boş sonuç gibi görünmez.

## Sigorta

`client.insurance` sepet kalemleriniz için sigorta sunar, satar ve yönetir (I1–I22). Her çağrı imzalıdır. `create_order`, `confirm_payment`, `issue_policy`, `cancel_order`, `refund_premium` ve `create_lead` bir `Idempotency-Key` ister (8–200 yazdırılabilir ASCII); `create_quote` ve `bind_payment` isteğe bağlı anahtar alır. Teklifin sepeti ya `paymentIntentId` ya da `context.items` olur, ikisi birden olmaz; bir sigorta türünün kendi nesnesinin alanlarını gateway doğrular (bütün alanlar tek seferde 422 `insurance.validation.invalid` ile).

```ruby
quote = lunixi.insurance.create_quote({ insuranceType: product['insuranceType'], currency: 'TRY', context: { items: basket_items } })
option = quote['options'].first
order = lunixi.insurance.create_order(
  { quoteId: option['quoteId'], consent: Lunixi::Insurance.consent_from_quote(option, accepted_at) }, idempotency_key: order_key
)
basket_items << Lunixi::Insurance.premium_basket_item(order, name: 'Insurance premium', category1: 'Insurance')
```

Poliçe belgeleri, makbuzlar ve sertifikalar PDF baytları olarak döner; `export_reconciliation` bir `Lunixi::InsuranceReconciliationExport` döndürür (`data`, `truncated?`, `next_cursor`, `aborted?`).

Banka hesabı, banka transferi ve sigorta webhook'ları imza denetiminden geçirilerek okunur:

```ruby
event = Lunixi::InsuranceWebhook.parse(raw_request_bytes, signature_headers, ENV.fetch('LUNIXI_WEBHOOK_SECRET'))
record_policy(event['insuranceOrderId'], event['policies']) if event.type == Lunixi::InsuranceEvents::POLICY_ISSUED
```

`Lunixi::BankConnectWebhook` `bank_account.transaction.received` olayını, `Lunixi::BankTransferWebhook` banka bağlantısının `bank_transfer.*` olaylarını (ödeme yönteminin `payment.bank_transfer.*` olaylarını değil), `Lunixi::InsuranceWebhook` ise sipariş olaylarını ve `insurance.lead.submitted` olayını okur. `event.data` yalnız belgelenmiş alanları taşır; `event.id` ile tekilleştirin.

## Abonelik

`client.subscriptions` yinelenen faturalamayı yürütür: planlar, müşteriler (kendi `externalId` değerinizle eklenir/güncellenir), saklı kartlar (kart numarasıyla değil, checkout SDK'sının `paymentMethodToken` değeriyle eklenir), abonelikler, faturalar, müşteri portalı, katalog ürünleri, özellikler, ek paketler ve ölçülen kullanım. Bu çağrılar yalnız erişim token'ını taşır. Abonelik oluşturma bir `Idempotency-Key` ister ve anahtar gövdede de gönderilir; plan, müşteri, kart, plan değişikliği ve tahsilat yeniden denemesi yazımları isteğe bağlı anahtar kabul eder. Gövdeler ve filtreler göndermeden önce `Lunixi::SUBSCRIPTION_ROUTES` ile denetlenir; gövdelerin, filtrelerin ve yanıtların para alanları kanonik küçük birim string'leri olmalıdır (ücretsiz plan için `"0"`).

```ruby
plan = lunixi.subscriptions.plans.create({ productId: product_id, code: 'pro', name: 'Pro', price: '9900', currency: 'TRY',
                                           billing: { frequency: 'MONTHLY' } }, idempotency_key: plan_key)
# Yenilemeler alıcıyı müşteri kaydından alır: kimlik ve fatura bilgileri zorunludur.
customer = lunixi.subscriptions.customers.upsert({ externalId: user.id, name: user.first_name, surname: user.last_name, email: user.email,
                                                   gsmNumber: user.phone, identityNumber: user.identity_number,
                                                   billingAddress: user.address, billingCity: user.city, billingCountry: user.country,
                                                   billingZipCode: user.zip_code })
subscription = lunixi.subscriptions.create({ customerId: customer['id'], planId: plan['id'] }, idempotency_key: signup.key)
grant_access! if Lunixi::Subscriptions.active?(subscription)
```

Abonelik, plan, müşteri, kart, fatura ve denetim kaydı listeleri, `next_cursor` değeri `page_token:` olarak geri gönderilen bir `Lunixi::ListPage` döndürür (`page_size` zarfın `pageSize` değeridir); `iterate` bütün sayfaları gezer. `portal.create_sdk_session` gömülü portal kanıtını döndürür (`portalToken`, `sessionProof`, `proofNonce`, `proofExpiresAt`); `portal.create_portal_link` barındırılan bir link döndürür, link `Lunixi::Subscriptions.portal_url(link)` ile açılır. Olay adları `Lunixi::SubscriptionEvents` içindedir. Eksik veya geçersiz müşteri alanı 400 `subscription.customer.field_required` / `subscription.customer.field_invalid` ile yanıtlanır (`Lunixi::SubscriptionCustomerErrorCode`).

## KYC ve kimlik sinyalleri

`client.kyc` KYC, KYB ve kanıt oturumlarını oluşturur ve yürütür; çekimi tarayıcı SDK'sı yayınlanabilir anahtarla yapar ve sonucun belirleyicisi `kyc.*` webhook'udur (`Lunixi::KycEvents`). `person:` / `company:`, `customerType` ile birlikte `customer` olarak; `metadata:` ise `evidenceContextJson` olarak gönderilir. `list_sessions` yalnız `limit` ve `cursor` alır (`pageSize` / `pageToken` aynı alanlar olarak okunur). Belge görseli hiçbir hata mesajında görünmez.

```ruby
session = lunixi.kyc.create_session({ subjectId: user.id, sessionType: Lunixi::KycSessionType::KYC, externalCustomerId: user.id,
                                      person: { firstName: user.first_name } }, idempotency_key: kyc_key)
approved = Lunixi::Kyc.assurance_meets?(achieved_level, Lunixi::KycAssuranceLevel::SUBSTANTIAL)
```

`client.identity` bir tarayıcı `traceId` değeri için cihaz ve hesap ilişkilendirme sinyallerini okur (karar değil; risk işaretleri ve gerekçe kodları). `Lunixi::Identity.device_shared?(links)` cihazı başka bir hesabın kullanıp kullanmadığını söyler; `Lunixi::Identity.link_reasons(links)` nedenlerini listeler. İki istemci de yalnız erişim token'ını taşır.

## Pazaryeri

`client.marketplace` bir tahsilatı alt bayiler arasında böler ve alt bayileri yönetir. Bölünmüş tahsilatlar (`create_checkout_intent`, `charge_marketplace_card2d`, `charge_marketplace_card3d`) imzalıdır ve isteğe bağlı idempotency anahtarı alır (16–128 yazdırılabilir ASCII); her alt bayi için bir parça, `{ subDealerId, amountMinor, scenario? }`, verin; parçaların toplamı `amount` değerine eşit olmalıdır (göndermeden önce denetlenir). Token veya form olmadan yanıtlanan checkout intent'i `ApiError` oluşturur. Kart verisi verildiği gibi gönderilir ve hiçbir hata mesajına konmaz; doğrudan kart tahsilatı yerine barındırılan formu (`create_checkout_intent`) tercih edin.

```ruby
intent = lunixi.marketplace.create_checkout_intent(
  { amount: '100000', currency: 'TRY', orderId: order.id, callbackUrl: return_url,
    buyer: buyer, billingAddress: billing_address, basketItems: basket_items }, # sipariş bilgileri, Ödeme başlatma örneğindeki gibi
  [{ subDealerId: 'd_alice', amountMinor: '60000' }, { subDealerId: 'd_bob', amountMinor: '40000' }],
  multi_seller_policy: Lunixi::MarketplaceMultiSellerPolicy::ALL_OR_NOTHING, idempotency_key: order.payment_key
)
```

Bayi, komisyon, hakediş ödemesi ve denetim kaydı rotaları yalnız erişim token'ını taşır: `create_dealer`, `bulk_create_dealers`, `list_dealers`, `get_dealer`, `update_dealer_status`, `onboarding_token` (`Lunixi::Marketplace.onboarding_url(link)`), `dealer_application`, `submit_dealer_application`, `set_dealer_terms`, `sign_dealer_contract`, `activate_dealer`, `record_dealer_kyc_result`, `payout_ledger`, `transactions`, `commission_rules`, `upsert_commission_rule`, `preview_commission_rule`, `resolve_commission`, `create_payout`, `mark_payout_paid`, `bulk_mark_payouts_paid`, `audit_log` ve `verify_audit_log`.

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

`Lunixi::Error` taban sınıftır. `ConfigurationError`, `SignatureError`, `TransportError`, `RedirectError`, `WebhookError`/`ReplayConflict`, `ApiError`, `AuthenticationError`, `ValidationError` ve `RateLimitError` ayrıştırılır. API hatası yalnız `status`, güvenli `code`, `request_id`, `retry_after` ve `details` (yalnız `field`, `allowedOperation` ve `retryAfterSeconds` tanımlayıcıları) sunar; gövde, özel anahtar ve karşı tarafın hata metni eklenmez.

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
