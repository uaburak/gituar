// Şarkılardan türeyen SEO kuralları (sayfalar ve site haritası). Veri yenilenince (catalogVersion) yeniden hesaplanır.
//  - Kopya şarkılar: akor içeriği birebir aynı olanlardan en eski (seq) ana sayfa, diğerleri ona canonical verir.
//  - İnce sanatçı sayfaları: tek şarkılı sanatçılar noindex ve site haritası dışı (şarkı sayfası zaten aynı içerik).
//  - Ton adları: eşsesli tonlar (G# / Ab) tek sayfada; daha çok şarkısı olan yazım asıl ad olur.
//  - Düetler: "A & B", "A ft. B" kayıtları, katalogda kendi sayfası olan sanatçıların sayfasında da listelenir.
import { catalog, catalogVersion } from "./catalog.ts";

const SHARPS = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
const FLATS = { Db: "C#", Eb: "D#", Gb: "F#", Ab: "G#", Bb: "A#", Cb: "B", Fb: "E", "E#": "F", "B#": "C" };
const MIN_THIN_ARTIST = 2;

let rules;
let rulesVersion = -1;

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
  if (rules && rulesVersion === catalogVersion()) return rules;
  rulesVersion = catalogVersion();
  const songs = catalog().songs;
  const songPath = (s) => `/akor/${s.artistSlug}/${s.slug}/`;

  // Kopyalar
  // ch: API'nin sadeleştirilmiş içerikten çıkardığı özet (kısa içerikte boş)
  const byContent = new Map();
  for (const s of [...songs].sort((a, b) => a.seq - b.seq)) {
    if (!s.ch) continue;
    if (!byContent.has(s.ch)) byContent.set(s.ch, s);
  }
  const canonicalOf = new Map();
  for (const s of songs) {
    const primary = s.ch ? byContent.get(s.ch) : undefined;
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

  rules = { canonicalOf, thinArtists, featuredIn, keyName, songCount: songs.length };
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

/**
 * Ton ve akor sayfası açma eşikleri katalog büyüklüğüne göre: büyük katalogda ince sayfa açılmasın (10 / 20 şarkı),
 * küçük katalogda (kullanıcılar yeni yüklerken) sayfalar yine oluşsun (2 şarkı).
 */
export function minKeySongs() {
  return load().songCount >= 2000 ? 10 : 2;
}
export function minChordSongs() {
  return load().songCount >= 2000 ? 20 : 2;
}
