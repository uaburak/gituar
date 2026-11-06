# Gituar Platform Planı — tek kaynak, web + iOS

Tarih: 2026-11-04 · Branch: `feature/web-platform`

## 1. Hedefler

- Tek bir arka uç (Firebase projesi `koc-chords`) hem iOS uygulamasını hem web sitesini besler.
- Öncelik hız: web sayfaları CDN'den statik HTML olarak gelir, iOS katalog uygulamanın içinde gelir.
- Ücretsiz kotalarda kalınır; Cloud Functions ve Cloud Storage kullanılmaz.
- Reklam gösterimi artar (web ve iOS), "Gituar Plus" aboneliği (aylık 99 TL) reklamları kaldırır.
- Web UX'i Repertuarım alışkanlıklarını korur (şarkı başına URL, ton şeridi, kapo, yazı boyutu, otomatik kaydırma, repertuara ekle), görsel dil iOS uygulamasının tonundadır.

## 2. Mimari

```
                 ┌──────────────────────────── Firebase (koc-chords) ───────────────────────────┐
                 │  Firestore                      Auth                    Hosting (CDN)        │
                 │  ├ songs/{id}      (admin yazar) │                       └ web/dist (statik) │
                 │  ├ catalog/meta    (seq sayacı)  │                                           │
                 │  ├ users, repertoires, user-chords, public-repertoires, preferences, reports │
                 └─────────▲──────────────▲─────────┴───────────────────────────▲───────────────┘
                           │ delta        │ kullanıcı verisi                     │ deploy
   iOS ─────────────────────┘              │                                     │
   • seed: Gituar/Resources/catalog.deflate (uygulamaya gömülü)                  │
   • açılışta: seq > lastSeq olan şarkıları çek, birleştir, diske yaz            │
                                           │                                     │
   Web (Astro, statik) ────────────────────┘                                     │
   • build: shared/catalog/catalog.deflate → şarkı başına HTML                   │
   • tarayıcıda: Firebase JS SDK ile giriş, repertuar, Plus durumu               │
                                                                                 │
   Yayın (Mac'te tek komut) ─────────────────────────────────────────────────────┘
   npm run publish  →  Firestore'dan delta çek → catalog.deflate güncelle → web build → firebase deploy
```

Kullanıcı istemcileri kataloğu Firestore'dan **hiç okumaz**; iOS yalnızca farkları okur, web çalışırken hiçbir şey okumaz.
Admin düzenlemeleri iOS uygulamasından Firestore'a yazılır. Her yazı `catalog/meta.seq` sayacını transaction ile artırır
ve şarkıya yeni `seq` değerini verir; bu sayaç iki istemcinin de "benden sonra ne değişti" sorusunun cevabıdır.

## 3. Veri modeli (Firestore)

| Koleksiyon / doküman | Alanlar | Kim yazar |
|---|---|---|
| `songs/{id}` | `artist`, `songName`, `originalKey`, `content`, `artistSlug`, `slug`, `status` ("approved"), `seq` (number), `deleted` (bool), `createdAt`, `updatedAt`, `addedBy`, `ownerId` | admin (uygulama), import scripti |
| `catalog/meta` | `seq` (number, tekil artan), `count`, `publishedAt` | admin transaction'ı, publish scripti |
| `users/{uid}` | mevcut alanlar + `plus: { active, until, source, productId }` | kullanıcı (kendi dokümanı) |
| `repertoires/{id}` | mevcut | sahibi |
| `user-chords/{id}` | mevcut | sahibi / admin |
| `public-repertoires`, `preferences`, `reports` | mevcut | mevcut kurallar |

Şarkı `id`'si eski docId ile aynı kalır (sayısal metin), repertuarlardaki `songIds` kırılmaz.
Silme `deleted: true` + yeni `seq` ile yapılır; böylece fark senkronu silmeyi de taşır.

Kurallar: `shared/firestore.rules`. `songs` herkes okur, yalnızca `users/{uid}.isAdmin == true` yazar.
`seq` alanı için tek alan indeksi yeterlidir (`where seq > x orderBy seq`), bileşik indeks gerekmez.

## 4. Katalog dağıtımı

### Dosya biçimi
`shared/catalog/catalog.deflate`: ham DEFLATE (zlib başlıksız) ile sıkıştırılmış JSON.
iOS tarafında `NSData.decompressed(using: .zlib)`, Node tarafında `zlib.inflateRawSync` açar.

```json
{ "seq": 13713, "count": 13713, "publishedAt": "2026-11-04T00:00:00Z",
  "songs": [ { "id": "956", "artist": "Zakkum", "songName": "Anason", "originalKey": "Dm",
               "content": "...", "artistSlug": "zakkum", "slug": "anason", "seq": 956 } ] }
```

Ölçülen: 13.713 şarkı → 18,2 MB JSON → 4,3 MB deflate. Storage'daki canlı `chords/chords_data.json` ile
yerel kopya bayt bayt aynı (MD5 `UXwRyKEtYLiKuJA7D4Pw2w==`), yani seed canlı resmi kataloğun tamamıdır.

### iOS
1. Açılışta `catalog.deflate` paketten açılır, anında hazır. Diskte daha yeni bir birleşik kopya varsa o yüklenir.
2. `songs where seq > lastSeq orderBy seq limit 500` sorgusu ile farklar çekilir, `deleted` olanlar çıkarılır, kalanlar
   üzerine yazılır, birleşik katalog diske (deflate) ve `lastSeq` UserDefaults'a yazılır.
3. Günlük açılışta fark yoksa sorgu 0 doküman döner; Firestore 0 okuma sayar. Yeni kurulum: sürümden beri değişen şarkı kadar okuma.

### Web
Astro build sırasında `catalog.deflate` açılır; her şarkı için `/akor/{artistSlug}/{slug}/` sayfası, her sanatçı için
`/sanatci/{artistSlug}/`, site haritası ve `search-index.json` (id, sanatçı, şarkı, slug; ~220 KB gzip) üretilir.
Arama tarayıcıda bu indeks üzerinde anında çalışır; Türkçe normalizasyon iOS ile aynıdır.

### Yayın akışı (Mac'te)
```
npm run catalog:seed      # tek seferlik: ../chords_data.json → catalog.deflate
npm run catalog:import    # tek seferlik: catalog.deflate → Firestore songs (500'lük batch'ler)
npm run catalog:pull      # Firestore'dan seq > snapshot.seq olanları çek, catalog.deflate'i güncelle
npm run build -w web      # statik site
firebase deploy --only hosting,firestore:rules
```
`catalog:pull` yalnızca değişen dokümanları okur; 17 bin okuma yalnızca ilk import'ta bir kez olur.

## 5. Web uygulaması

- Stack: Astro 5 (statik çıktı), TypeScript, saf CSS (tasarım tokenları), Firebase JS SDK (yalnızca etkileşimli adalar).
- URL yapısı: `/` · `/akor/{sanatci}/{sarki}/` · `/sanatci/{sanatci}/` · `/sanatcilar/` · `/ara/?q=` · `/repertuar/{id}/` · `/repertuarlarim/` · `/giris/` · `/plus/`
- Şarkı sayfası (Repertuarım alışkanlığı): başlık, kontrol çubuğu (Orijinal ton, Kapo, Akorlar aç/kapat, Repertuara ekle,
  Sayfayı oynat, Yazı boyutu +A/−A), ton şeridi C…B, akor satırları vurgulu, altında sanatçının diğer şarkıları ve benzerleri.
- Görsel dil: Wecra "Gituar" dosyasındaki tokenlar (`global.css` :root) — sayfa #FBFBFD, yüzey #FFF, metin #1D1D1F / #6E6E73,
  vurgu #0071E3; listeler kartsız, ince çizgili satırlar; üst bar 960×56 yüzen cam şerit (logo + menü solda, "Ara /" + Giriş +
  App Store sağda); gece modu düğmesi alt bilgide.
- Performans (ölçülen, tam katalog): 16.957 sayfa 17 sn'de derlenir. Şarkı sayfası HTML 4,7 KB gzip, sayfa JS'i 3,7 KB gzip,
  CSS 3,4 KB gzip. Firebase SDK yalnızca daha önce giriş yapmış ziyaretçide ya da Repertuara ekle'ye basınca yüklenir.
  Arama indeksi 345 KB gzip, yalnızca arama/rastgele butonunda indirilir.
- App Store: her sayfada Safari'nin yerel Smart App Banner'ı (`apple-itunes-app`, app-id 6764865998). Şarkı sayfalarında
  `app-argument=gituar://song/{id}` ile uygulama yüklüyse doğrudan o şarkı açılır (mevcut deep link). Header'da App Store butonu,
  sağ sütunda indirme kartı.
- Şarkı içeriği HTML'de düz metin olarak durur (SEO), transpoze tarayıcıda `shared/src/chords.ts` ile.

### Firebase tarafı (2026-11-05)

- Firestore kuralları tek kaynak: `shared/firestore.rules` → `firebase deploy --only firestore:rules`. Console'daki
  19 Mayıs 2026 kurallarıyla birleştirildi (songs/catalog fark senkronu, `metadata/admins`, isAdmin yükseltme koruması).
- `metadata/admins` (`uids: [...]`, herkese açık okunur, yalnızca admin yazar): "Editörün seçimleri" = bu kullanıcıların
  `public-repertoires` kayıtları. Web ana sayfa bunu Firestore REST ile SDK yüklemeden okur; iOS da önce buraya bakar.
- Web repertuarları iOS ile aynı yerde: özel `users/{uid}/repertoires`, herkese açık `public-repertoires`.
- Web yönetim paneli `/admin/` (yalnızca `users/{uid}.isAdmin`): onay bekleyen `user-chords` (onayla/reddet) ve
  `reports` (incelemeye al / çözüldü / yoksay). Üst bardaki "Yönetim" bağlantısı sadece admin'de görünür.
- Authentication: Google, Apple ve E-posta/Şifre açık; yetkili alanlar localhost, koc-chords.firebaseapp.com, koc-chords.web.app.
- Web Firebase ayarları `web/.env` (gitignore'da): `firebase apps:sdkconfig WEB 1:890664830560:web:e0bf44d1cf5e0a7b96e505`.

### Tasarım (2026-11-05, Apple tarzı revizyon)

- Varsayılan tema aydınlık; sistem tercihi izlenmez. Koyu tema yalnızca üst bardaki ay/güneş düğmesiyle
  (`data-theme="dark"`, localStorage `gituar-theme`). Tokenlar Apple paleti: zemin #f5f5f7 (gri), beyaz kutular #fff
  (listeler, kartlar, akor sayfası, özellik kutuları), ikincil yüzey #e8e8ed, metin #1d1d1f / #6e6e73, vurgu #0071e3,
  çizgi #d2d2d7; koyu: #000 zemin / #1d1d1f kutular / #2c2c2e / #f5f5f7 / #0a84ff. (2026-11-06: tam beyaz zemin
  istenmedi, apple.com gibi gri zemin + beyaz kutu düzenine geçildi.)
- Üst bar: tam genişlik 48 px cam şerit (Apple nav), 1024 px iç genişlik; logo, menü, kompakt arama, giriş,
  App Store, tema düğmesi; mobilde menü açılır paneli düz zeminli.
- Karşılama ortalı, 56 px başlık; kartlar gri ve kenarlıksız (18 px); alt bilgi gri, 12 px.
- Reklamsız sayfalar (`ads={false}`) `.shell-plain` ile tek sütun; dolmayan AdSense birimleri gizlenir.
- Wecra "Gituar" dosyası bu revizyonu henüz içermiyor (designer bağlantısı kapalıydı); açılınca eşitlenmeli.

### Yayın (2026-11-05)

- Web **Vercel**'de yayınlanır: proje `gituar.com` (takım uaburaks-projects), alan adı gituar.com/www zaten projede, DNS Vercel.
  Asıl yayın: GitHub `uaburak/gituar` main'e push → Vercel build (kök `vercel.json`: `cd web && npm ci && npm run build`, çıktı `web/dist`;
  PUBLIC_* ortam değişkenleri Vercel projesinde tanımlı). Bunun için Vercel → Settings → Git'te eski `gituar-web` deposu
  kesilip `uaburak/gituar` bağlanmalı (CLI/otomasyon bu adımı yapamadı). Yedek yol: `web/` içinde `npm run deploy` (= `vercel build --prod` yerelde Astro build + `vercel deploy --prebuilt --prod`;
  Vercel'de build çalışmaz, `web/vercel.json` framework/trailingSlash/önbellek başlıklarını taşır). Bir kez `vercel login`
  ve `vercel link --project gituar.com` gerekir (`.vercel/` gitignore'da). Vercel CLI `~/.npm-global/bin/vercel`.
- Firebase Hosting artık yalnızca `koc-chords.web.app → https://gituar.com` 301 yönlendirmesi (`firebase-redirect/`,
  `firebase deploy --only hosting`). Firebase = Firestore + Auth (+ Storage); Auth yetkili alanlarına gituar.com eklendi.
- Vercel projesi hâlâ eski açılış sayfasının deposuna (uaburak/gituar-web) bağlı; o bağlantı Vercel → Settings → Git →
  Disconnect ile kesilmeli, yoksa o depoya gelen push yeni siteyi ezer.
- SEO: `docs/SEO.md` (başlık/açıklama şablonları, JSON-LD, sitemap-index, robots). Search Console doğrulaması için
  `PUBLIC_GSC_VERIFICATION` env'i.

## 6. Reklam planı

Web düzeni (Wecra "Gituar" dosyası, 2026-11-04 revizesi): içerik 960 px ortada, iki yanda 160×600 reklam sütunu
(≥ 1400 px genişlikte görünür, kaydırmada sabit), üstte reklam bandı ve sağ sütun yok, üst bar yüzen cam şerit.

| Yer | Web | iOS (AdMob) |
|---|---|---|
| Her sayfa (masaüstü) | sol ve sağ 160×600 (sticky); Giriş/İletişim/404'te yok | — |
| Şarkı sayfası | akor sayfasının altında 300×250 (duyarlı) | satır içi yerel reklam: biri şarkının başında, biri şarkı biter bitmez (oynatma modunda ikisi de gizli); her 4. şarkı açılışında geçiş reklamı (en az 90 sn ara) |
| Listeler (ana, sanatçı) | her 10 satırda bir liste içi | Tüm Şarkılar, genel listeler ve Sanatçılar'da her 10 satırda bir yerel (native) reklam |
| Telefon (≤ 900 px) | alt yapışkan 320×50 | — |
| Uygulama açılışı | yok | app open reklamı günde en fazla 3 |
| Plus | tüm slotlar DOM'dan çıkar | hiçbir reklam yüklenmez |

Web'de Google AdSense (`web/src/components/AdSlot.astro` tek noktadan; yan sütunlar `layouts/Base.astro` içinde),
iOS'ta mevcut AdMobManager + `AdPlacements`.

**Durum (2026-11-05):**
- AdMob (yayıncı `pub-9748717269838207`, uygulama `~8786045485`): banner `/3275621944`, yerel `/4478703611`,
  geçiş "Geçiş - Şarkı" `/7548725985`, açılış "Açılış" `/7980357868` (`AdConfig`). DEBUG'da Google test birimleri.
- AdSense (2026-11-05): hesap AdMob yayıncısıyla açıldı (`ca-pub-9748717269838207`), site `gituar.com` eklendi
  (inceleme bekliyor; `koc-chords.web.app` kaydı silinebilir). Birimler: yan 160×600 `9146099877`, akor altı (duyarlı)
  `3469880177`, liste içi (duyarlı) `1076038163`, mobil alt 320×50 `6819107404` → `web/.env` PUBLIC_ADSENSE_SLOT_*.
  Doğrulama: her sayfada `google-adsense-account` meta + `ads.txt`. Reklamlar site onayından sonra çıkar.
Repertuarım'daki gibi uzun oturumlar için şarkı sayfasında reklam 60 sn'de bir yenilenir (görünür olduğunda).

## 7. Gituar Plus — aylık 99 TL

- iOS: StoreKit 2 otomatik yenilenen abonelik, ürün kimliği `com.gituar.plus.monthly`, App Store Connect'te 99 TL.
  `PlusManager` `Transaction.currentEntitlements` ile durumu izler, `users/{uid}.plus` alanını Firestore'a yazar.
- Web: kullanıcı giriş yaptığında `users/{uid}.plus.until > now` ise reklamlar yüklenmez. Web'de satış ikinci fazdadır:
  Türkiye'de Stripe yayıncı hesabı açılamadığından iyzico/PayTR gerekir ve bu da sunucu tarafı webhook ister.
- Sunucusuz doğrulama sınırı: Firestore'daki `plus` alanını kullanıcı kendi yazar; sahtecilik riski reklamsızlık kadar düşüktür.
  Hacim büyürse RevenueCat (aylık 2.500 $ gelire kadar ücretsiz) ile makbuz doğrulaması eklenir.

## 8. Maliyet (Blaze sıfır maliyet kotaları)

| Servis | Ücretsiz | Bu tasarımda |
|---|---|---|
| Firestore okuma | 50k/gün | iOS fark senkronu: değişen şarkı kadar; web: 0 |
| Firestore yazma | 20k/gün | admin düzenlemeleri; ilk import 13,7k bir kez |
| Hosting | 10 GB depo, 10 GB/ay | 17k sayfa ≈ 400 MB; ~1M görüntüleme/ay gzip ile |
| Auth | sınırsız e-posta/Apple/Google | mevcut |

Hosting trafiği aşılırsa aynı `web/dist` Cloudflare Pages'e sınırsız trafikle taşınır, kod değişmez.

## 9. Fazlar

1. **Bu branch:** plan, `shared/` (şema, kurallar, scriptler, chords.ts), `web/` (tasarım sistemi, sayfalar, arama, reklam alanları,
   Plus kapısı), iOS `ChordsStorageManager` → seed + delta, `PlusManager`, `AdPlacements`.
2. Firestore'a import, App Store Connect'te abonelik ürünü, AdSense başvurusu, Hosting'e ilk deploy.
3. Web'de repertuar düzenleme, versiyon/ritim gibi Repertuarım özellikleri, web ödeme (iyzico) için küçük bir sunucu.

## 10. Kodun dışında yapılacaklar (sırayla)

1. **Firestore kuralları:** `shared/firestore.rules` dosyasını Console'daki mevcut kurallarla karşılaştırıp birleştirin, sonra
   `firebase deploy --only firestore:rules`. Bu yapılmadan iOS fark senkronu "Missing or insufficient permissions" verir
   (simülatörde görüldü); uygulama yine gömülü katalogla çalışır.
2. **Katalog import:** Firebase Console → Project settings → Service accounts → anahtar indir;
   `GOOGLE_APPLICATION_CREDENTIALS=anahtar.json npm run catalog:import`. 13.713 yazma, günlük 20k ücretsiz kotanın içinde, bir kez.
3. **Web Firebase uygulaması:** Console → Project settings → Add app → Web. Değerleri `web/.env` dosyasına
   (`web/.env.example` şablon). Authentication → Settings → Authorized domains'e Hosting alanını ekleyin.
4. **Abonelik:** App Store Connect → Subscriptions → grup "Gituar Plus", ürün `com.gituar.plus.monthly`, 99 TL/ay.
5. **AdMob:** geçiş (interstitial) ve uygulama açılış (app open) birimlerini oluşturup `AdPlacements.swift` içindeki
   `REPLACE_*` kimliklerini değiştirin. Release derlemede bu iki format kimlik girilene kadar gösterilmez.
6. **AdSense:** site yayına girince başvurun, yayıncı kimliğini `PUBLIC_ADSENSE_CLIENT` olarak girin; slot kimlikleri `AdSlot` bileşeninde.
7. **Yayın:** `npm run publish -- --deploy` (farkları çeker, iOS seed'i günceller, siteyi derler, Hosting'e yükler).
   Her App Store sürümünden önce `npm run catalog:ios` ile seed'i tazeleyin.
