// Sitemap <lastmod>: şarkının API'deki güncellenme zamanı; sanatçı sayfası için şarkılarının en yenisi.
// Astro config'i Vite alias'ları olmadan yüklendiği için .cache/songs.json doğrudan okunur.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

let map;

function load() {
  if (map) return map;
  map = new Map();
  try {
    const songs = JSON.parse(readFileSync(fileURLToPath(new URL("./.cache/songs.json", import.meta.url)), "utf8"));
    const artistLatest = new Map();
    for (const s of songs) {
      const date = s.updatedAt ?? s.createdAt;
      if (!date) continue;
      map.set(`/akor/${s.artistSlug}/${s.slug}/`, date);
      const prev = artistLatest.get(s.artistSlug);
      if (!prev || date > prev) artistLatest.set(s.artistSlug, date);
    }
    for (const [slug, date] of artistLatest) map.set(`/sanatci/${slug}/`, date);
  } catch (err) {
    console.warn("[sitemap] lastmod için şarkılar okunamadı:", err?.message ?? err);
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
