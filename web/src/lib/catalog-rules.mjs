// Katalogdan türeyen SEO kuralları. Hem sayfalar (Astro) hem astro.config.mjs (site haritası) bunu kullanır;
// config Vite alias'ları olmadan yüklendiği için düz JS ve snapshot'ı kendisi açar.
//  - Kopya şarkılar: akor içeriği birebir aynı olanlardan en eski (seq) ana sayfa, diğerleri ona canonical verir.
//  - İnce sanatçı sayfaları: tek şarkılı sanatçılar noindex ve site haritası dışı (şarkı sayfası zaten aynı içerik).
//  - Ton adları: eşsesli tonlar (G# / Ab) tek sayfada; daha çok şarkısı olan yazım asıl ad olur.
//  - Düetler: "A & B", "A ft. B" kayıtları, katalogda kendi sayfası olan sanatçıların sayfasında da listelenir.
import { inflateRawSync } from "node:zlib";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const SHARPS = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
const FLATS = { Db: "C#", Eb: "D#", Gb: "F#", Ab: "G#", Bb: "A#", Cb: "B", Fb: "E", "E#": "F", "B#": "C" };
const MIN_THIN_ARTIST = 2;

let rules;

function normalizeContent(text) {
  return (text ?? "").replace(/\r/g, "").replace(/[ \t]+/g, " ").replace(/\n{2,}/g, "\n").trim();
}

/** "G#m" → "G#m", "Abm" → "G#m": eşsesli tonların ortak anahtarı. Ton değilse null. */
export function keyClass(key) {
  const m = /^([A-G])(#|b)?(m)?$/.exec((key ?? "").trim());
  if (!m) return null;
  let root = m[1] + (m[2] ?? "");
  if (FLATS[root]) root = FLATS[root];
  return SHARPS.includes(root) ? root + (m[3] ?? "") : null;
}

/** "Burak Bulut & Kurtuluş Kuş", "Simge ft. Murda" → ["Burak Bulut", "Kurtuluş Kuş"] */
export function creditParts(name) {
  return (name ?? "")
    .split(/\s*(?:&|,|\+|\bfeat\.?\s|\bft\.?\s|\bfeaturing\s|\bvs\.?\s)\s*/i)
    .map((p) => p.trim())
    .filter(Boolean);
}

function load() {
  if (rules) return rules;
  const path = fileURLToPath(new URL("../../../shared/catalog/catalog.deflate", import.meta.url));
  const snapshot = JSON.parse(inflateRawSync(readFileSync(path)).toString("utf8"));
  const songs = snapshot.songs.filter((s) => !s.deleted);
  const songPath = (s) => `/akor/${s.artistSlug}/${s.slug}/`;

  // Kopyalar
  const byContent = new Map();
  for (const s of [...songs].sort((a, b) => a.seq - b.seq)) {
    const k = normalizeContent(s.content);
    if (k.length < 40) continue;
    if (!byContent.has(k)) byContent.set(k, s);
  }
  const canonicalOf = new Map();
  for (const s of songs) {
    const primary = byContent.get(normalizeContent(s.content));
    if (primary && primary.id !== s.id) canonicalOf.set(songPath(s), songPath(primary));
  }

  // Sanatçılar
  const artistCount = new Map();
  const artistName = new Map();
  for (const s of songs) {
    artistCount.set(s.artistSlug, (artistCount.get(s.artistSlug) ?? 0) + 1);
    artistName.set(s.artistSlug, s.artist);
  }
  const thinArtists = new Set([...artistCount].filter(([, n]) => n < MIN_THIN_ARTIST).map(([slug]) => slug));

  // Düetler: parça adı → sanatçı slug'ı (yalnızca kendi kaydı olan sanatçılar)
  const slugByName = new Map();
  for (const [slug, name] of artistName) slugByName.set(name.toLocaleLowerCase("tr-TR"), slug);
  const featuredIn = new Map(); // slug → şarkı id'leri
  for (const s of songs) {
    const names = new Set(creditParts(s.artist));
    const ft = /\((?:ft\.?|feat\.?)\s+([^)]+)\)/i.exec(s.songName ?? "");
    if (ft) for (const p of creditParts(ft[1])) names.add(p);
    for (const n of names) {
      const slug = slugByName.get(n.toLocaleLowerCase("tr-TR"));
      if (!slug || slug === s.artistSlug) continue;
      if (!featuredIn.has(slug)) featuredIn.set(slug, []);
      featuredIn.get(slug).push(s.id);
    }
  }
  // Düetleri listelenen sanatçının sayfası artık tek şarkı değil; ince sayılmaz.
  for (const slug of featuredIn.keys()) thinArtists.delete(slug);

  // Tonlar: eşsesli grupta asıl yazım
  const keyCounts = new Map();
  for (const s of songs) {
    const k = (s.originalKey ?? "").trim();
    const c = keyClass(k);
    if (!c) continue;
    if (!keyCounts.has(c)) keyCounts.set(c, new Map());
    const m = keyCounts.get(c);
    m.set(k, (m.get(k) ?? 0) + 1);
  }
  const keyName = new Map(); // sınıf → { name, spellings, total }
  for (const [c, m] of keyCounts) {
    const spellings = [...m.entries()].sort((a, b) => b[1] - a[1]);
    keyName.set(c, { name: spellings[0][0], spellings: spellings.map(([k]) => k), total: spellings.reduce((t, [, n]) => t + n, 0) });
  }

  rules = { canonicalOf, thinArtists, featuredIn, keyName };
  return rules;
}

/** Kopya şarkı sayfası için asıl sayfanın yolu; kopya değilse undefined. */
export function canonicalSongPath(path) {
  return load().canonicalOf.get(path);
}

export function isThinArtist(slug) {
  return load().thinArtists.has(slug);
}

/** Bu sanatçının düet olarak geçtiği (başka kayıtlı) şarkıların id'leri. */
export function featuredSongIds(slug) {
  return load().featuredIn.get(slug) ?? [];
}

/** Ton sınıfının asıl adı ve tüm yazımları: keyInfo("Ab") → { name: "G#", spellings: ["G#", "Ab"], total } */
export function keyInfo(key) {
  const c = keyClass(key);
  return c ? load().keyName.get(c) : undefined;
}

export function allKeyInfos() {
  return [...load().keyName.values()];
}

/** Site haritasına girmemesi gereken (noindex ya da canonical başka sayfa) yollar. */
export function excludedFromSitemap(pathname) {
  const r = load();
  if (r.canonicalOf.has(pathname)) return true;
  const m = /^\/sanatci\/([^/]+)\/$/.exec(pathname);
  return Boolean(m && r.thinArtists.has(m[1]));
}
