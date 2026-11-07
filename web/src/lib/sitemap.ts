// Site haritası girdileri: sabit sayfalar + veritabanındaki şarkı, sanatçı, ton, akor ve liste sayfaları.
// noindex olanlar (ince sanatçı, kopya şarkı, arama, giriş, yönetim…) dahil edilmez.
import { catalog, catalogVersion } from "./catalog.ts";
import { excludedFromSitemap, allKeyInfos, minKeySongs } from "./catalog-rules.mjs";
import { chordPages, easySongs, songChords } from "./chord-stats.ts";
import { keySlug } from "./keys.ts";
import { songPath, artistPath } from "./paths.ts";

export const SITEMAP_CHUNK = 5000;

const STATIC = [
  "/", "/sanatcilar/", "/akorlar/", "/kolay-gitar-akorlari/", "/kapo-ile-kolay-sarkilar/", "/ton/", "/yeni-eklenenler/", "/populer-akorlar/",
  "/editorun-secimleri/", "/rehber/", "/rehber/akor-transpoze/", "/rehber/kapo/", "/rehber/ukulele-akorlari/",
  "/rehber/en-cok-kullanilan-akorlar/", "/pro/", "/hakkinda/", "/iletisim/", "/kullanim-sartlari/", "/gizlilik/",
];

let cached: { version: number; base: string; entries: { loc: string; lastmod?: string }[] } | null = null;

export function sitemapEntries(base: string): { loc: string; lastmod?: string }[] {
  if (cached && cached.version === catalogVersion() && cached.base === base) return cached.entries;
  const c = catalog();
  const out: { loc: string; lastmod?: string }[] = STATIC.map((p) => ({ loc: base + p }));
  const artistLatest = new Map<string, string>();
  for (const s of c.songs) {
    const path = songPath(s);
    const lastmod = s.updatedAt ?? s.createdAt;
    if (lastmod && (!artistLatest.has(s.artistSlug) || lastmod > artistLatest.get(s.artistSlug)!)) artistLatest.set(s.artistSlug, lastmod);
    if (!excludedFromSitemap(path)) out.push({ loc: base + path, lastmod });
  }
  for (const a of c.artists) {
    const path = artistPath(a.slug);
    if (!excludedFromSitemap(path)) out.push({ loc: base + path, lastmod: artistLatest.get(a.slug) });
  }
  for (const k of allKeyInfos()) if (k.total >= minKeySongs()) out.push({ loc: `${base}/ton/${keySlug(k.name)}/` });
  for (const ch of chordPages()) out.push({ loc: `${base}/akorlar/${ch.slug}/` });
  const easy = easySongs();
  for (const n of [2, 3, 4]) if (easy.filter((s) => songChords(s).chords.length === n).length >= 10) out.push({ loc: `${base}/kolay-gitar-akorlari/${n}-akorlu-sarkilar/` });
  cached = { version: catalogVersion(), base, entries: out };
  return out;
}
