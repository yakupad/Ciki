# Çıkı — App Store sayfası planı

Bu klasördeki her görsel **kurgusal örnek hane** (Deniz ve Ece) ile alınmıştır. Kişi, banka ve tutarlar uydurmadır. Görseller yeniden üretilirken de gerçek veri kullanılmaz.

## Klasör yapısı

| Yol | İçerik |
| --- | --- |
| `metadata/{tr,en-US}/` | Ad, alt başlık, tanıtım metni, açıklama, anahtar kelimeler ve sürüm notları (fastlane `deliver` biçimi) |
| `screenshots/{tr,en-US}/<cihaz>/` | Başlıklı mağaza ekran görüntüleri (JPEG, alfa kanalı yok) |
| `creative/{tr,en-US}/` | Asset Library görselleri: ürün sayfası başlığı, arama sonucu ve evrensel görsel |
| `asset-library.json` | Tüm görsellerin listesi: ölçü, dil, yerleşim, hangi CPP ve PPO testinde kullanıldığı |
| `tools/` | Üretim betikleri: `content.py` (metinler ve plan) ve `compose.swift` (çizim) |

Görselleri yeniden üretmek için:

```sh
python3 tools/content.py <ham-görüntü-klasörü>   # tools/jobs.json + asset-library.json
swift tools/compose.swift tools/jobs.json
```

Ham görüntüler DEBUG derlemesinden `-loadSampleData` ile alınır. Durum çubuğu 9:41'e sabitlenir.

### App Store Connect'e yükleme

`tools/asc/` altındaki betikler App Store Connect API ile çalışır. Anahtar bilgileri ortam değişkenlerinden okunur ve repoya yazılmaz: `ASC_KEY_ID`, `ASC_ISSUER_ID` ve `ASC_KEY_PATH` (`.p8` dosyasının yolu).

| Betik | Ne yapar |
| --- | --- |
| `metadata.rb` | Kategori, ad, alt başlık, açıklama, anahtar kelimeler ve tanıtım metni (iOS ve macOS, TR ve EN) |
| `screenshots.rb` | Ekran görüntüleri; setteki eskileri silip yeniden yükler |
| `cpp.rb` | Özel ürün sayfaları ve sayfa başına ekran görüntüsü sırası |
| `creative.rb` | Asset Library'ye başlık, arama ve evrensel görseller |
| `placements.rb` | Başlık ve arama görsellerini varsayılan sayfaya ve özel sayfalara bağlar |

Asset Library ürün sayfası başlığı ve evrensel görsel için JPEG kabul etmiyor (`INVALID_ASSET_FILE_FORMAT`). Bu yüzden ikisi PNG olarak üretilir. Arama görseli JPEG olarak kabul ediliyor.

## Metinler

| | Türkçe | English |
| --- | --- | --- |
| Ad (≤30) | Çıkı: Ortak Bütçe | Çıkı: Shared Budget |
| Alt başlık (≤30) | Borç, ödeme ve kira takibi | Bills, debts and rent tracker |
| Kategori | Finans (birincil), Verimlilik (ikincil) | Finance, Productivity |

Anahtar kelimeler, ad ve alt başlıkta geçen sözcükleri tekrar etmez (App Store bunları zaten dizine ekler). "Çıkı" adı Türkçe klavye olmadan "Ciki" diye de aranır. Apple aksanları eşleştirdiği için ayrıca eklenmedi.

**Bağlantılar:** gizlilik politikası https://yakupad.github.io/Ciki/privacy/ ve destek https://yakupad.github.io/Ciki/support/ . Sayfalar bu deponun `docs/` klasöründen GitHub Pages ile yayınlanır. Sorun bildirimleri deponun Issues sekmesine gelir.

**App Privacy (Gizlilik etiketi):** "Veri toplanmaz" (Data Not Collected). Uygulama hiçbir sunucuya veri göndermez. iCloud verisi kullanıcının kendi hesabındadır ve Apple'ın tanımına göre geliştiricinin topladığı veri sayılmaz. TCMB kur isteği kişisel veri içermez.

**Yaş derecelendirmesi:** 4+. Sorulara hepsi "Hayır" yanıtıyla geçilir. Kumar ya da kredi verme olmadığı için finans soruları da "Hayır" olarak işaretlenir.

## Ekran görüntüleri

Varsayılan sıra ve başlıklar:

| # | Ekran | Türkçe başlık | English headline |
| --- | --- | --- | --- |
| 1 | Özet | Ay sonunu bugünden gör | See your month-end today |
| 2 | Aylar | Ödendi mi? Kaydır, geç | Paid? Just swipe |
| 3 | Tablo | Excel tablon artık cebinde | Your spreadsheet, in your pocket |
| 4 | Karşılama | Hanece, birlikte | Shared with your household |
| 5 | Rapor | Paran nereye gidiyor, gör | See where your money goes |
| 6 | Kalemler | TL, dolar, euro bir arada | Lira, dollar and euro together |

| Cihaz | Ölçü | Adet | Not |
| --- | --- | --- | --- |
| iPhone 6.9" | 1320×2868 | 6 | Daha küçük iPhone'lara otomatik ölçeklenir |
| iPhone 6.3" | 1206×2622 | 6 | Zorunlu |
| iPad 13" | 2064×2752 | 3 | Zorunlu (uygulama iPad'i destekliyor) |
| Mac | 2880×1800 | 3 | Zorunlu (Mac Catalyst) |
| Apple Watch Ultra | 422×514 | 2 | Başlıksız, ham görüntü |
| iPhone Duo (iç ekran) | 2853×2007 | 1 | Apple'a göre yükleme bu yıl içinde açılacak |
| iPhone Duo (dış ekran) | 1398×2034 | 1 | Apple'a göre yükleme bu yıl içinde açılacak |

## Asset Library

App Store Connect'in yeni **Asset Library** bölümü, görselleri bir kez yükleyip varsayılan sayfada, özel ürün sayfalarında (CPP) ve testlerde (PPO) yeniden kullanmayı sağlar.

| Görsel | Ölçü | Yerleşim | Kullanım |
| --- | --- | --- | --- |
| `header-urun` | 3840×1646 | Ürün sayfası başlığı | Varsayılan, tüm CPP'ler, PPO Test 2 kontrolü |
| `header-marka` | 3840×1646 | Ürün sayfası başlığı | PPO Test 2 varyasyonu |
| `search-varsayilan` | 3840×2560 | Arama sonucu | Varsayılan |
| `search-<cpp>` | 3840×2560 | Arama sonucu | İlgili CPP |
| `universal` | 5244×2950 | Evrensel görsel (Today, öne çıkanlar) | Editoryal öneri ve App Store reklamları |

Apple'ın içerik kuralları: görsellerde fiyat, URL, © ya da doğrulanamayan ödül ve sıralama iddiası olmamalı. Önemli öğeler ortada tutulmalı, çünkü kenarlar cihaza göre kırpılır. Hazırlanan görseller bu kurallara uyar.

## Özel ürün sayfaları (Custom Product Pages)

Her sayfa kendi arama anahtar kelimelerine bağlanır. Böylece o aramayı yapan kişi kendisine en uygun mesajı görür. Bağlantılar reklam kampanyalarında ve sosyal medyada da kullanılabilir.

| Kimlik | Hedef kitle | İlk ekran | Arama görseli başlığı | Anahtar kelimeler |
| --- | --- | --- | --- | --- |
| `aile` | Eşi ya da ailesiyle bütçe yönetenler | Karşılama | Ailenin bütçesi, birlikte | aile bütçesi, ev bütçesi, ortak bütçe, eş |
| `ev-arkadaslari` | Kira, aidat ve faturaları paylaşanlar | Aylar | Kira ve faturalar, ortak | ev arkadaşı, kira paylaşımı, fatura bölüşme, aidat |
| `kart-borc` | Kart ekstresi ve kredi taksiti takip edenler | Aylar | Kart ve kredi borcunu yönet | kredi kartı, ekstre, kredi taksiti, borç takibi |
| `doviz` | Euro ya da dolarla düzenli ödeme yapanlar | Kalemler | Döviz ödemeleri, TL karşılığıyla | döviz, euro, dolar, kur, iban |

Tanıtım metinleri ve sayfa başına ekran görüntüsü sırası `asset-library.json` içindedir. Her sayfanın İngilizce karşılığı da tanımlıdır.

**Anahtar kelime bağlama:** API özel sayfalara arama anahtar kelimesi bağlamayı destekliyor. Ancak bağlanabilecek kelimeler, uygulamanın onaylanmış sürümündeki anahtar kelimelerden gelir. Bu yüzden ilk sürüm onaylandıktan sonra yapılabilir.

**İsteğe bağlı derin bağlantı:** Bir CPP uygulamayı ilgili ekranda açabilir (örneğin `doviz` → Kalemler). Bunun için uygulamaya bir URL şeması ya da Universal Link eklenmesi gerekir. Şu an tanımlı değil.

## Ürün sayfası optimizasyonu (PPO)

Testler uygulama yayındayken başlatılabilir. Aynı anda tek test çalışır. Her test en az 14 gün sürer ve App Store Connect en fazla 90 gün izin verir.

**Test 1 — İlk ekran görüntüsünün mesajı** (Türkçe, trafik dört eşit parça)

| Grup | İlk ekran | Mesaj |
| --- | --- | --- |
| Kontrol | Özet | Ay sonunu bugünden gör |
| A | Tablo | Excel tablon artık cebinde |
| B | Karşılama | Hanece, birlikte |
| C | Aylar | Ödendi mi? Kaydır, geç |

Hipotez: Excel alışkanlığını ya da birlikte kullanımı öne çıkaran bir ilk görsel, genel özetten daha çok indirme getirir. Kazanan varyasyon kontrolden en az %90 güvenle iyiyse varsayılan sıra olur.

**Test 2 — Başlık görseli** (Türkçe ve İngilizce, %50/%50): uygulama ekranlarını gösteren `header-urun` ile ikon odaklı `header-marka` karşılaştırılır.

**Test 3 — İkon (ileride):** Alternatif ikonlar uygulama paketinde bulunmalıdır. Önce amber bağın daha baskın olduğu bir varyasyon tasarlanır, sonra yeni bir sürümle gönderilir ve ardından test edilir.

**Ölçüm:** App Store Connect → Analytics → Product Page Optimization ekranında dönüşüm oranı ve iyileşme yüzdesi izlenir. CPP'ler için aynı ekranda sayfa bazında gösterim ve indirme verisi görülür.
