// /llms.txt: yapay zekâ asistanları için site özeti (llmstxt.org). Sözler bilinçli olarak yok; yalnızca yapı ve bağlantılar.
import type { APIRoute } from "astro";
import { topArtists } from "../lib/catalog.ts";
import { artistPath } from "@shared/catalog";
import { APP_STORE_URL, INSTAGRAM_URL } from "../lib/site.ts";

export const GET: APIRoute = ({ site }) => {
  const base = (site?.href ?? "https://gituar.com/").replace(/\/$/, "");
  const artists = topArtists(25).map((a) => `- [${a.name} akorları](${base}${artistPath(a.slug)})`);
  const body = `# Gituar

> Türkçe şarkıların gitar akorları; akorları kullanıcılar ekler, editörler onaylar. Ücretsiz; transpoze, kapo hesabı, otomatik kaydırma ve repertuarlar. Web (gituar.com) ve iPhone uygulaması aynı kataloğu kullanır.

## Temel bilgiler

- Dil: Türkçe
- Şarkı sayfası adresi: ${base}/akor/{sanatçı}/{şarkı}/ (akorlar, orijinal ton, kullanılan akorlar)
- Sanatçı sayfası adresi: ${base}/sanatci/{sanatçı}/
- Akorlar müzik eğitimi amacıyla yayımlanır; eserlerin hakları sahiplerine aittir.
- iPhone uygulaması: ${APP_STORE_URL}
- Instagram: ${INSTAGRAM_URL}
- İletişim: info@gituar.com

## Ana bölümler

- [Sanatçılar A'dan Z'ye](${base}/sanatcilar/): tüm sanatçıların akorları
- [Gitar akorları sözlüğü](${base}/akorlar/): akorların nasıl basıldığı ve o akorla çalınan şarkılar
- [Kolay gitar akorları](${base}/kolay-gitar-akorlari/): yalnızca açık akorlarla çalınan şarkılar
- [Tona göre şarkılar](${base}/ton/): majör ve minör tonlarda şarkı listeleri
- [Editörün Seçimleri](${base}/editorun-secimleri/): popüler gitar şarkısı listeleri
- [Yeni eklenenler](${base}/yeni-eklenenler/)
- [Rehber](${base}/rehber/): akor transpoze, kapo, ukulele

## Öne çıkan sanatçılar

${artists.join("\n")}

## Yasal

- [Hakkında ve SSS](${base}/hakkinda/)
- [Kullanım Şartları](${base}/kullanim-sartlari/)
- [Gizlilik ve Çerez Politikası](${base}/gizlilik/)
`;
  return new Response(body, { headers: { "Content-Type": "text/plain; charset=utf-8" } });
};
