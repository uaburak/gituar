// Sitemap <lastmod> kaynağı (astro.config.mjs → sitemap.serialize).
// Şarkı: createdAt varsa o, yoksa kataloğun yayın tarihi (snapshot.publishedAt).
// Sanatçı: şarkılarının en yeni tarihi. Ana sayfa ve sanatçı dizini: yayın tarihi.
// Astro config'i Vite alias'ları olmadan yüklendiği için snapshot burada doğrudan açılır.
import { inflateRawSync } from "node:zlib";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

let map;

function isoDate(value) {
  const t = Date.parse(value ?? "");
  return Number.isNaN(t) ? undefined : new Date(t).toISOString();
}

function load() {
  if (map) return map;
  map = new Map();
  try {
    const path = fileURLToPath(new URL("../shared/catalog/catalog.deflate", import.meta.url));
    const snapshot = JSON.parse(inflateRawSync(readFileSync(path)).toString("utf8"));
    const published = isoDate(snapshot.publishedAt);
    const artistLatest = new Map();
    for (const s of snapshot.songs) {
      if (s.deleted) continue;
      const date = isoDate(s.createdAt) ?? published;
      if (!date) continue;
      map.set(`/akor/${s.artistSlug}/${s.slug}/`, date);
      const prev = artistLatest.get(s.artistSlug);
      if (!prev || date > prev) artistLatest.set(s.artistSlug, date);
    }
    for (const [slug, date] of artistLatest) map.set(`/sanatci/${slug}/`, date);
    if (published) {
      map.set("/", published);
      map.set("/sanatcilar/", published);
    }
  } catch (err) {
    console.warn("[sitemap] lastmod için katalog okunamadı:", err?.message ?? err);
  }
  return map;
}

/** Mutlak URL için ISO lastmod; bilinmeyen sayfalarda undefined (lastmod yazılmaz). */
export function sitemapLastmod(url) {
  try {
    return load().get(new URL(url).pathname);
  } catch {
    return undefined;
  }
}
