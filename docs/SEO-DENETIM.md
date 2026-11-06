# SEO denetimi — 6 Kasım 2026

GitHub'da en çok yıldız alan dört SEO skill'i ayrı ayrı çalıştırıldı. Her biri gituar.com'u ve 16.998 sayfalık derlemeyi
kendi yöntemiyle taradı. Skill'lerin betikleri çalıştırılmadı; yalnızca kontrol listeleri kullanıldı.

| Skill | Yıldız | Odak |
|---|---|---|
| AgriciDaniel/claude-seo | 26.9k | Teknik, şema, programatik sayfalar |
| zubair-trabzada/geo-seo-claude | 11.5k | Yapay zekâ aramaları (GEO), llms.txt, alıntılanabilirlik |
| Bhanunamikaze/Agentic-SEO-Skill | 1.0k | Site geneli teknik tarama, ince içerik, performans |
| Illyism/seo-skills | 0.7k | Başlık/CTR, içerik boşlukları |

Parantez içindeki sayı, bulguyu kaç skill'in bulduğunu gösterir.

## Sorunsuz çıkanlar

Kopya başlık ve açıklama yok, her sayfada tek H1 ve kendi canonical'ı var, kırık iç bağlantı yok, şarkılar ana sayfadan
en fazla 3 tıkta, JSON-LD hatasız ayrıştırılıyor, görsellerin hepsinde alt metin var, 404 sayfası gerçek 404 dönüyor,
yapay zekâ tarayıcıları engellenmemiş, içerik sunucuda üretiliyor.

## Düzeltmeler

| # | Bulgu | Skill | Durum |
|---|---|---|---|
| 1 | Ton ve rehber sayfalarında JSON-LD dizisinde `@context` eksik | (3) | yapıldı |
| 2 | Site haritası filtresi köke bağlı değil; `/akor/zeynep-bastik/ara/` haritadan düşüyor | (1) | yapıldı |
| 3 | Aynı tonun iki adı ayrı sayfa (`g-diyez` / `a-bemol` gibi) | (2) | yapıldı |
| 4 | Gizlilik ve hakkında sayfası yok (AdSense için de gerekli) | (2) | yapıldı |
| 5 | `/akor/`, `/akor/{sanatçı}/`, `/sanatci/` 404 dönüyor | (2) | yapıldı |
| 6 | Şarkı sayfasında "Repertuara ekle" H2 başlık olarak işaretli | (4) | yapıldı |
| 7 | 768 şarkı başlığı 60 karakteri aşıyor | (2) | yapıldı |
| 8 | Organization şemasında `sameAs` yok, logo SVG | (3) | yapıldı |
| 9 | `llms.txt` yok | (3) | yapıldı |
| 10 | Tek şarkılı 1.886 sanatçı sayfası ince ve şarkı sayfasının kopyası | (3) | yapıldı: noindex + haritadan çıkarıldı |
| 11 | Byte düzeyinde aynı akor sayfaları (200 grup) | (2) | yapıldı: canonical ana sayfaya |
| 12 | Site haritasındaki tüm `lastmod` tarihleri aynı | (4) | yapıldı: sahte tarih kaldırıldı |
| 13 | `/editorun-secimleri/` içeriği tarayıcıda yükleniyor, sunucu HTML'i boş | (1) | yapıldı: build sırasında üretiliyor |
| 14 | Güvenlik başlıkları eksik (Referrer-Policy, X-Frame-Options) | (2) | yapıldı |
| 15 | Ana sayfa H1'i gizli, içerik ince | (2) | yapıldı |
| 16 | `www.gituar.com` yönlendirmiyor | (3) | Vercel → Domains ayarı, kullanıcıda |
| 17 | Aynı şarkının `-2` kopyaları, bölünmüş sanatçılar (`coldplay` / `cold-play`) | (2) | katalog temizliği gerekiyor |
| 18 | Düet sanatçıları ayrı sayfa (`… & …`, `ft.`) | (2) | kısmen: ana sanatçı sayfasında "birlikte söyledikleri" |
| 19 | `/sanatcilar/` 10 bin DOM öğesi, harf sayfalarına bölünmeli | (2) | sırada |
| 20 | IndexNow | (2) | Bing kaydıyla birlikte, sırada |

## Yeni sayfa türleri (katalogdaki akorlardan)

Ölçülen veri: 13.713 şarkıda 345 farklı akor (eşsesliler birleşik), 75'i en az 20 şarkıda. 831 şarkı yalnızca açık
akorlarla çalınıyor, 2.100'den fazlası kapo ile açık akorlara iniyor. 1.742 şarkı en fazla 3 akorlu.

| Sayfa | Hedef arama | Skill | Durum |
|---|---|---|---|
| `/akorlar/` ve `/akorlar/{akor}/`: diyagram, nasıl basılır, bu akorla çalınan şarkılar | "am akoru", "f akoru nasıl basılır" | (4) | yapıldı |
| Şarkı sayfasında akor diyagramları, zorluk etiketi, "Kapo X ile kolay" | "{şarkı} akor" | (3) | yapıldı |
| `/kolay-gitar-akorlari/` ve 2/3/4 akorlu alt sayfalar | "kolay gitar akorları" | (4) | yapıldı |
| `/barresiz-sarkilar/` | "barresiz şarkılar" | (2) | yapıldı |
| `/kapo-ile-kolay-sarkilar/` | "kapo ile kolay şarkılar" | (2) | yapıldı |
| Sanatçı sayfasında özet: en çok kullanılan ton ve akorlar, en kolay şarkılar | "{sanatçı} akorları" | (3) | yapıldı |
| `/yeni-eklenenler/` | tazelik | (1) | yapıldı |
| `/rehber/en-cok-kullanilan-akorlar/`: katalog istatistikleri | alıntılanabilir veri | (1) | yapıldı |
| Akor dizisi sayfaları (`am-g-f-e`), en az 20 şarkılı olanlar | "… akorlarıyla çalınan şarkılar" | (2) | sırada |
| Tür / dönem sayfaları | — | (2) | katalogda tür alanı yok |

## Kullanıcının yapacakları

- Vercel → Settings → Domains: `www.gituar.com` → `gituar.com` kalıcı yönlendirme.
- Bing Webmaster Tools: Search Console'dan içe aktar.
- Marka sinyali: YouTube, Instagram, TikTok, Ekşi Sözlük ve forumlarda gituar.com; App Store açıklamasına bağlantı.
- Search Console'da 4 hafta veri birikince başlık testleri (8–20. sıradaki sorgular).
