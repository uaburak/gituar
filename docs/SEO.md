# Gituar Web — SEO Planı ve Uygulaması

Tarih: 2026-11-05 · Branch: `feature/web-platform` · Site: https://gituar.com (Astro 5, statik, Firebase Hosting)

Hedef: Türkçe gitar akoru aramalarında ("akor", "gitar akorları", "{şarkı} akor", "{sanatçı} akorları", "akor transpoze",
"kapo") üst sıralar. Katalog 13.713 şarkı / 3.235 sanatçı; SEO'nun taşıyıcısı ~13.700 şarkı sayfasıdır.

Kod: şablonlar ve JSON-LD üreticileri `web/src/lib/seo.ts`, head etiketleri `web/src/layouts/Base.astro`,
sitemap `web/astro.config.mjs` + `web/sitemap-lastmod.mjs`, `web/public/robots.txt`.

## 1. Anahtar kelime haritası

| Kelime grubu | Hedef sayfa | Nerede geçer |
|---|---|---|
| gitar akorları, gitar akor, akor, şarkı akorları, Türkçe gitar akorları | `/` | title, H1 ("Türkçe gitar akorları"), hero metni, alt bilgi bölümü, bölüm başlıkları |
| akor transpoze, kapo, otomatik kaydırma, ukulele akor | `/` alt bilgi bölümü; her şarkı sayfasının tanıtım paragrafı ve meta açıklaması | body metni, description |
| {şarkı} akor, {şarkı} akorları, {sanatçı} {şarkı} akor, {şarkı} gitar akoru | `/akor/{sanatçı}/{şarkı}/` | title, H1 ("{Şarkı} akorları"), description, breadcrumb, tanıtım paragrafı, JSON-LD |
| {sanatçı} akorları, {sanatçı} gitar akorları, {sanatçı} şarkıları akor | `/sanatci/{sanatçı}/` | title, H1 ("{Sanatçı} akorları"), description, ItemList, şarkı sayfalarından "Tüm {Sanatçı} akorları" bağlantıları |
| sanatçı akorları, akor sanatçı listesi | `/sanatcilar/` | title, H1 ("Sanatçı akorları"), ana sayfa ve alt bilgi bağlantıları |
| ton bazlı: "{Ton} tonunda şarkılar" | şarkı sayfası "E tonunda benzer şarkı akorları" bölümü (ayrı sayfa yok, bkz. yol haritası) | H2 |
| reklamsız akor, Gituar Plus | `/plus/` | title, description |

Bağlantı metinleri (anchor) her listede "{Şarkı} akorları" / "{Sanatçı} akorları" biçimindedir: `SongRow.astro` ve
`ArtistRow.astro` ada `.row-kw` ("akorları") ekler; `.row-title` yalnızca adı taşır ki `song-filter.ts` / `artist-filter.ts`
filtreleri bozulmasın.

## 2. Başlık ve açıklama şablonları

Base.astro her başlığa ` · Gituar` ekler; `fitTitle()` bu ekle birlikte 60 karaktere sığan ilk adayı seçer.
Açıklamalar 155 karaktere sığacak biçimde isteğe bağlı parçaları (akor listesi, örnek şarkılar) kısaltır.

| Sayfa | Title (adaylar, uzundan kısaya) | Description | H1 |
|---|---|---|---|
| Şarkı | `{Sanatçı} - {Şarkı} - Akor` (" · Gituar" eki yok; 60 karakteri aşarsa feat. kısmı atılır, sonra `{Şarkı} - Akor`) | `{Şarkı} akorları – {Sanatçı} şarkısının gitar akorları, orijinal ton {Ton}. Akorlar: Am, F, C, G. Transpoze, kapo ve otomatik kaydırma ile çal.` (akor listesi sığana kadar kısalır) | `{Şarkı} - Akor` (tek yazı tipi); altında sanatçı/ton satırı ve SEO paragrafı |
| Sanatçı | `{Sanatçı} Akorları – {N} Şarkı` → `{Sanatçı} Akorları` | `{Sanatçı} gitar akorları: {N} şarkı, orijinal ton bilgisiyle. {İlk 4 şarkı} ve daha fazlası. Transpoze ve kapo ile çal.` | `{Sanatçı} akorları` |
| Ana sayfa | `Gitar Akorları – {N} Türkçe Şarkı Akoru` | `Gitar akorları: {N} Türkçe şarkı akoru, {M} sanatçı. Akor transpoze, kapo ve otomatik kaydırma ile çal, repertuar oluştur. iOS uygulamasıyla aynı katalog.` | `Türkçe gitar akorları` |
| Sanatçılar | `Sanatçılar – Gitar Akorları A'dan Z'ye` | `{M} sanatçının gitar akorları alfabetik dizinde. Sanatçıyı seç, şarkı akorlarını orijinal tonuyla gör; transpoze ve kapo ile çal.` | `Sanatçı akorları` |
| Plus | `Plus – Reklamsız gitar akorları` | fiyat ve App Store bilgisi | `Gituar Plus` |
| Ara, Giriş, Repertuarlarım, Repertuar, Yönetim, İletişim, 404 | mevcut kısa başlıklar | — | — (`noindex`) |

300 şarkılık deneme derlemesinde: başlık en fazla 71 karakter (13/353 sayfa 60'ı aşar — en kısa aday bile sığmıyor,
Google keser), açıklama en fazla 159 (1 sayfa). Tam katalogda çok uzun şarkı adı 24 tanedir; kabul edilen durum.

Şarkı sayfasındaki tanıtım paragrafı (`.song-intro`) kalıp metindir ama kısadır ve her sayfada değişen veri taşır
(ad, sanatçı bağlantısı, ton, içerikten `usedChords()` ile çıkarılan akor listesi). Kullanılan akorlar
`shared/src/chords.ts` tespitiyle (`parse` + `chordSpans`) ilk görülme sırasına göre, en çok 12 tane.

## 3. Yapısal veri (JSON-LD) kararları

Tek `<script type="application/ld+json">`, `@graph` ile; `jsonLdText()` `<` karakterini `<` yapar.

- **Şarkı:** `MusicComposition { name, url, mainEntityOfPage, inLanguage?, musicalKey, isAccessibleForFree: true,
  recordedAs: MusicRecording { name, byArtist: MusicGroup { @id, name, url } } }` + `BreadcrumbList`
  (Ana sayfa › Sanatçılar › Sanatçı › Şarkı akorları).
  - `composer` kullanılmadı: katalogdaki "artist" seslendiren sanatçıdır, besteci bilgisi yok. `byArtist`
    MusicRecording'e ait olduğu için `recordedAs` üzerinden bağlanır (schema.org'a uygun, uydurma alan yok).
  - `inLanguage: "tr"` yalnızca sözlerde en az 3 Türkçeye özgü harf (ç ğ ı ö ş ü) varsa yazılır; katalogda ~1.058
    yabancı şarkı var, onlara dil yazılmaz.
- **Sanatçı:** `MusicGroup { @id, name, url, mainEntityOfPage }` + `ItemList` (tüm şarkılar; `ListItem { position,
  name: "{Şarkı} akorları", url }`, en büyük sanatçı 109 şarkı) + `BreadcrumbList`.
- **Ana sayfa:** `WebSite` (SearchAction → `/ara/?q={search_term_string}`), `Organization` (logo `/favicon.svg`,
  e-posta iletişim sayfasındaki adres), `SoftwareApplication` (iOS, MusicApplication, App Store id 6764865998,
  ücretsiz indirme → `Offer price 0 TRY`). Puan/yorum gibi elimizde olmayan alanlar yazılmadı.
  Not: Google "sitelinks search box" zengin sonucunu 2024'te kaldırdı; SearchAction yine geçerli ve zararsız.
- **Sanatçılar dizini:** `CollectionPage` + `BreadcrumbList`.
- Doğrulama: https://search.google.com/test/rich-results ve https://validator.schema.org.

## 4. Teknik kararlar

- `lang="tr"`, canonical (trailing slash, `Astro.site`), `og:site_name`, `og:locale=tr_TR`, `og:type`
  (`music.song` şarkı, `profile` sanatçı, `website` diğer), `music:musician` (şarkı → sanatçı URL'si),
  `twitter:card` (`summary`; `web/public/og.png` 1200×630 eklenirse `og:image` + `summary_large_image` otomatik).
- `noindex` (Base.astro prop): `/ara/`, `/giris/`, `/repertuarlarim/`, `/repertuar/`, `/admin/`, `/iletisim/`, `404`.
  Aynı liste `astro.config.mjs` sitemap `filter`'ında dışarıda bırakılır; robots.txt kullanıcıya özel ve arama
  sayfalarını (`/admin/ /giris/ /repertuarlarim/ /repertuar/ /ara/ /search-index.json`) engeller. İletişim sayfası
  taranabilir ama indekslenmez (telif bildirimi için erişilebilir kalsın).
- Sitemap: `@astrojs/sitemap`, `entryLimit: 5000` → `sitemap-index.xml` + `sitemap-0..3.xml` (~16.950 URL).
  `lastmod`: şarkıda `createdAt` varsa o, yoksa `catalog.deflate` içindeki `publishedAt`; sanatçı sayfası şarkılarının
  en yenisi; ana sayfa ve dizin yayın tarihi. Bugünkü snapshot'ta `createdAt` alanı hiç yok, bu yüzden hepsi
  `publishedAt` olarak çıkar (katalog yeniden yayımlanınca otomatik güncellenir).
- 404: Astro `dist/404.html` üretir, Firebase Hosting bunu 404 koduyla sunar; sayfa `noindex`.
- Search Console: `web/.env` içine `PUBLIC_GSC_VERIFICATION=<content değeri>` yazılınca Base.astro
  `<meta name="google-site-verification">` basar. `web/public/` altına HTML doğrulama dosyası konmadı.
- Harici font yok, görsel yok (ikonlar satır içi SVG), ek istemci JS eklenmedi; `white-space: pre` akor gösterimi ve
  `web/src/scripts/` dokunulmadı.

## 5. İç bağlantı

- Ana sayfa → Sanatçılar dizini (3 bağlantı: chip "Sanatçı akorları", "Sanatçıya göre bul", "Tüm sanatçı akorları"),
  popüler 8 sanatçı ("{Sanatçı} akorları"), yeni 10 şarkı ("{Şarkı} akorları"), alt bilgi bölümü (dizin, App Store,
  iletişim).
- Şarkı sayfası → breadcrumb (Ana sayfa / Sanatçılar / Sanatçı), sanatçı adı iki kez bağlantılı (meta satırı ve
  tanıtım paragrafı), "{Ton} tonunda benzer şarkı akorları" (5 farklı sanatçıdan, deterministik), "{Sanatçı} akorları"
  (8 şarkı + "Tüm {Sanatçı} akorları (N)").
- Sanatçı sayfası → breadcrumb, tüm şarkılar ("{Şarkı} akorları"), altta dizin ve iletişim bağlantısı.
- Sanatçılar dizini → her sanatçı (`title="{Sanatçı} akorları"`).

## 6. Doğrulama

```sh
cd web && CATALOG_LIMIT=300 npm run build      # ~5 sn; tam derleme dakikalar sürer
node -e 'const h=require("fs").readFileSync("dist/akor/zulfu-livaneli/zamandir-simdi/index.html","utf8");
  for (const m of h.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)) console.log(JSON.parse(m[1]));'
grep -o "<title>[^<]*</title>" dist/index.html
cat dist/robots.txt dist/sitemap-index.xml; ls dist/404.html
```

2026-11-05 sonucu (300 şarkı): 353 sayfa, JSON-LD parse hatası 0, tüm indekslenebilir sayfalarda tek H1, noindex
sayfalar sitemap dışında, `lastmod` tüm katalog URL'lerinde var.

## 7. Durum ve yol haritası

**Yapıldı (2026-11-06, `feature/web-platform`, henüz yayında değil):**
- Search Console mülkü `https://gituar.com/` eklendi. Doğrulama için iki yol hazır: `web/public/googlecdcd87f95c2b68bd.html`
  dosyası ve `PUBLIC_GSC_VERIFICATION` meta etiketi (`web/.env`). Yayından sonra Search Console'da DOĞRULA'ya basılır,
  ardından `https://gituar.com/sitemap-index.xml` gönderilir.
- Paylaşım görseli `web/public/og.png` (1200×630). Kaynağı `/og/` sayfası (noindex, sitemap dışı); değişirse headless
  Chrome ile yeniden çekilir:
  `"Google Chrome" --headless=new --window-size=1200,630 --screenshot=web/public/og.png http://localhost:3000/og/`
- Ton sayfaları `/ton/` ve `/ton/{slug}/` (en az 10 şarkılı 33 ton; `a-minor`, `c-diyez-minor` gibi). Şarkı sayfasındaki
  "benzer şarkılar" başlığı ilgili ton sayfasına bağlanır.
- Rehberler `/rehber/`, `/rehber/akor-transpoze/`, `/rehber/kapo/`, `/rehber/ukulele-akorlari/` (Article + FAQPage +
  breadcrumb JSON-LD). Alt bilgide "Tonlar" ve "Rehber", ana sayfa özellik kutularında rehber bağlantıları var.

**Sırada:**
1. **Bing Webmaster Tools:** Search Console'dan içe aktar, aynı sitemap.
2. **Backlink:** App Store sayfası, sosyal profiller ve müzik forumlarında gituar.com; Repertuarım kullanıcılarına
   duyuru; gitar eğitmeni blogları/YouTube açıklamalarına şarkı sayfası bağlantıları.
3. **İçerik:** popüler sanatçı/şarkı derlemeleri (editör repertuarları statik sayfa olarak); yeni rehberler
   ("ritim kalıpları", "bare akor").
4. **Veri:** yeni şarkılarda `createdAt` yazılması sitemap `lastmod` ve "yeni eklenenler" için değerli; yabancı
   şarkılarda `inLanguage` için gerekirse katalogda açık dil alanı.
5. **Performans:** Core Web Vitals'ı Search Console'dan izle; reklam alanlarının sabit yüksekliği CLS için korunmalı.
6. **Teknik takip:** çok uzun başlıklı 24 şarkı için elle kısa başlık alanı (`seoTitle`); `/ara/` bilinçli olarak
   indekslenmez. `www.gituar.com` → `gituar.com` yönlendirmesi Vercel alan adı ayarından yapılmalı.
