// Şarkı erişimi (sunucu tarafı).
//
// Worker belleğinde yalnızca hafif DİZİN tutulur: her şarkının adı, sanatçısı, tonu, akor listesi ve içerik özeti.
// Şarkı metni (içerik) dizinde yok; şarkı sayfası açılınca yalnızca o şarkı için istenir (songWithContent).
//
// Güncel kalma (30 bin şarkıdan 1'i değişince 30 bini yeniden indirmemek için):
//  1. En fazla CHECK_MS'de bir, arka planda katalog sürümü sorulur (/v1/version: son değişiklik zamanı + şarkı sayısı).
//  2. Sürüm aynıysa hiçbir şey yapılmaz.
//  3. Değiştiyse yalnızca son bilinen zamandan sonra değişen satırlar alınır (/v1/changes) ve dizine işlenir;
//     yayından kalkanlar çıkarılır. Şarkı sayısı tutmazsa (silinen var) numara listesiyle karşılaştırılıp ayıklanır.
//  4. Tam dizin yalnızca Worker ilk açıldığında ya da çok sayıda değişiklikte (toplu yükleme) indirilir; o da
//     sürüm adresli olduğu için Cloudflare önbelleğinden gelir.
// Ziyaretçi hiçbir zaman bu işlemleri beklemez (Worker'ın ilk isteği hariç).
import { groupByArtist, songPath, artistPath, type ArtistGroup } from "./paths.ts";
import type { CatalogSong } from "@shared/types";
import { API_URL } from "./site.ts";

/** Dizindeki şarkı. `content` dizinde boştur; metin için songWithContent(). */
export type ApiSong = CatalogSong & {
  score?: number;
  updatedAt?: string;
  /** updatedAt (ms): içerik isteğinin sürüm anahtarı */
  updatedMs: number;
  ownerId?: string;
  /** Kâğıttaki akorlar, ilk görülme sırasıyla, boşlukla ayrık (API türetir) */
  chords: string;
  /** Sadeleştirilmiş içeriğin özeti (kopya tespiti); kısa içerikte boş */
  ch: string;
  rhythm?: string;
  arpeggio?: string;
  tempo?: number;
  meter?: string;
};

interface Catalog {
  songs: ApiSong[];
  artists: ArtistGroup[];
  artistBySlug: Map<string, ArtistGroup>;
  byId: Map<string, ApiSong>;
  bySlug: Map<string, ApiSong>;
}

interface Version { v: string; max: number; count: number }

const CHECK_MS = 20_000; // sürüm kontrolü aralığı
const SCORES_MS = 5 * 60_000; // popülerlik puanları (sürümü değiştirmez) bu aralıkla tazelenir
const PAGE = 2000;

let songs = new Map<string, ApiSong>();
let cache: Catalog | null = null;
let current: Version | null = null;
let version = 0; // her dizin değişiminde artar (türetilmiş hesapların önbellekleri buna bakar)
let checkedAt = 0;
let scoresAt = 0;
let inflight: Promise<void> | null = null;

// ---------- Ağ ----------

type CacheStorageCf = CacheStorage & { default?: Cache };
function edgeCache(): Cache | undefined {
  try {
    return (globalThis.caches as CacheStorageCf | undefined)?.default;
  } catch {
    return undefined;
  }
}

/**
 * API'den JSON. Cloudflare'de yanıt bu veri merkezinin önbelleğine de konur (API'nin Cache-Control süresi kadar):
 * aynı merkezdeki diğer Worker örnekleri API'ye gitmeden alır. Sürüm adresli (v=) istekler kalıcıdır.
 */
async function getJson<T>(path: string): Promise<T> {
  const url = `${API_URL}${path}`;
  const cache = edgeCache();
  if (cache) {
    const hit = await cache.match(url).catch(() => undefined);
    if (hit) return (await hit.json()) as T;
  }
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Şarkı API'si yanıt vermedi (${res.status}) ${path}`);
  if (cache && /max-age=[1-9]/.test(res.headers.get("Cache-Control") ?? "")) {
    const copy = res.clone();
    await cache.put(url, new Response(copy.body, { headers: { "Content-Type": "application/json", "Cache-Control": copy.headers.get("Cache-Control")! } })).catch(() => {});
  }
  return (await res.json()) as T;
}

function toSong(s: Record<string, unknown>): ApiSong {
  return {
    id: s.id as string,
    artist: s.artist as string,
    songName: s.title as string,
    originalKey: (s.originalKey as string) ?? "",
    content: (s.content as string) ?? "",
    artistSlug: s.artistSlug as string,
    slug: s.slug as string,
    seq: s.createdAt as number,
    createdAt: new Date(s.createdAt as number).toISOString(),
    updatedAt: new Date(s.updatedAt as number).toISOString(),
    updatedMs: s.updatedAt as number,
    score: (s.score as number) ?? 0,
    chords: (s.chords as string) ?? "",
    ch: (s.ch as string) ?? "",
    ...(s.addedBy ? { addedBy: s.addedBy as string } : {}),
    ...(s.ownerId ? { ownerId: s.ownerId as string } : {}),
    ...(s.rhythm ? { rhythm: s.rhythm as string } : {}),
    ...(s.arpeggio ? { arpeggio: s.arpeggio as string } : {}),
    ...(s.tempo ? { tempo: s.tempo as number } : {}),
    ...(s.meter ? { meter: s.meter as string } : {}),
  };
}

// ---------- Dizin ----------

async function fullLoad(v?: Version): Promise<void> {
  const ver = v ?? (await getJson<Version>("/v1/version"));
  const next = new Map<string, ApiSong>();
  for (let offset = 0; ; offset += PAGE) {
    const page = await getJson<{ songs: Record<string, unknown>[] }>(`/v1/index?v=${ver.v}&limit=${PAGE}&offset=${offset}`);
    for (const s of page.songs) next.set(s.id as string, toSong(s));
    if (page.songs.length < PAGE) break;
  }
  songs = next;
  current = ver;
  scoresAt = Date.now();
  rebuild();
}

/** Sürüm değiştiyse yalnızca değişenleri işler. */
async function refresh(): Promise<void> {
  const ver = await getJson<Version>("/v1/version");
  if (current && ver.v === current.v) return;
  if (!current) return fullLoad(ver);

  const res = await getJson<{ songs: Record<string, unknown>[]; more: boolean }>(`/v1/changes?since=${current.max}&v=${ver.v}`);
  // Toplu değişiklikte (ör. büyük yükleme) parça parça uğraşmak yerine tam dizin (o da önbellekten)
  if (res.more) return fullLoad(ver);
  for (const row of res.songs) {
    if (row.status === "approved") songs.set(row.id as string, toSong(row));
    else songs.delete(row.id as string);
  }
  if (songs.size !== ver.count) {
    // Silinen şarkı var: yayındaki numaralarla karşılaştır
    const { ids } = await getJson<{ ids: string[] }>(`/v1/ids?v=${ver.v}`);
    const live = new Set(ids);
    for (const id of [...songs.keys()]) if (!live.has(id)) songs.delete(id);
    if (songs.size !== ver.count) return fullLoad(ver);
  }
  current = ver;
  rebuild();
}

/** Popülerlik puanları: sürümü değiştirmez, yerinde güncellenir (sıralamalar istek anında hesaplanır). */
async function refreshScores(): Promise<void> {
  const { scores } = await getJson<{ scores: [string, number][] }>("/v1/scores");
  const map = new Map(scores);
  for (const s of songs.values()) s.score = map.get(s.id) ?? 0;
  scoresAt = Date.now();
}

function rebuild(): void {
  const list = [...songs.values()];
  const artists = groupByArtist(list);
  cache = {
    songs: list,
    artists,
    artistBySlug: new Map(artists.map((a) => [a.slug, a])),
    byId: songs,
    bySlug: new Map(list.map((s) => [`${s.artistSlug}/${s.slug}`, s])),
  };
  version++;
}

/**
 * Dizini hazırlar. Bellekte varsa hemen döner; CHECK_MS geçtiyse sürüm kontrolü arka planda yapılır
 * (ziyaretçi beklemez). Yalnızca hiç dizin yokken (Worker'ın ilk isteği) bekler. API hata verirse eldeki dizinle devam edilir.
 * `waitUntil`: Cloudflare'de yanıt gittikten sonra da arka plan işinin bitmesini sağlar.
 */
export async function loadCatalog(waitUntil?: (p: Promise<unknown>) => void): Promise<void> {
  const now = Date.now();
  if (cache && now - checkedAt < CHECK_MS) return;
  if (!inflight) {
    checkedAt = now;
    const job = cache ? refresh().then(() => (Date.now() - scoresAt > SCORES_MS ? refreshScores() : undefined)) : fullLoad();
    inflight = job
      .catch((e) => {
        if (!cache) throw e;
        console.warn("[catalog] güncellenemedi, eldeki dizin kullanılıyor:", (e as Error).message);
      })
      .finally(() => { inflight = null; });
  }
  if (cache) {
    waitUntil?.(inflight);
    return;
  }
  await inflight;
}

export function catalog(): Catalog {
  if (!cache) throw new Error("catalog() loadCatalog() tamamlanmadan çağrıldı");
  return cache;
}

/** Her dizin değişiminde artar; türetilmiş hesapların önbellekleri buna bakar. */
export function catalogVersion(): number {
  return version;
}

// ---------- Şarkı metni (yalnızca açılan şarkı) ----------

const CONTENT_MAX = 400;
const contents = new Map<string, ApiSong>(); // anahtar: id@updatedMs (sürüm değişince eski kayıt kendiliğinden geçersiz)

/**
 * Şarkının metni ve ritim bilgisiyle tam hâli. Sürüm (updatedMs) adresin parçası: aynı sürüm Cloudflare önbelleğinden
 * ve Worker belleğinden gelir; şarkı düzenlenince yeni sürüm istenir, diğer şarkılara dokunulmaz.
 */
export async function songWithContent(song: ApiSong): Promise<ApiSong> {
  const key = `${song.id}@${song.updatedMs}`;
  const hit = contents.get(key);
  if (hit) {
    contents.delete(key);
    contents.set(key, hit); // en son kullanılan sona
    return hit;
  }
  const { song: raw } = await getJson<{ song: Record<string, unknown> }>(
    `/v1/songs/by-slug/${encodeURIComponent(song.artistSlug)}/${encodeURIComponent(song.slug)}?v=${song.updatedMs}`,
  );
  const full: ApiSong = { ...song, ...toSong({ ...raw, chords: song.chords, ch: song.ch }), score: song.score };
  contents.set(key, full);
  if (contents.size > CONTENT_MAX) contents.delete(contents.keys().next().value!);
  return full;
}

// ---------- Sorgular ----------

export function songBySlug(artistSlug: string, slug: string): ApiSong | undefined {
  return catalog().bySlug.get(`${artistSlug}/${slug}`);
}

export function newestSongs(n: number): ApiSong[] {
  return [...catalog().songs].sort((a, b) => b.seq - a.seq).slice(0, n);
}

export function topArtists(n: number): ArtistGroup[] {
  return [...catalog().artists].sort((a, b) => b.songs.length - a.songs.length).slice(0, n);
}

/** Aynı tondaki başka sanatçıların şarkıları; seq'e bağlı deterministik seçim. */
export function sameKeySongs(song: CatalogSong, n: number): CatalogSong[] {
  const pool = catalog().songs.filter((s) => s.originalKey === song.originalKey && s.artistSlug !== song.artistSlug);
  if (pool.length <= n) return pool;
  const out: CatalogSong[] = [];
  let x = song.seq * 2654435761 % pool.length;
  const step = 7919 % pool.length || 1;
  const seen = new Set<number>();
  while (out.length < n && seen.size < pool.length) {
    if (!seen.has(x)) {
      seen.add(x);
      out.push(pool[x]);
    }
    x = (x + step) % pool.length;
  }
  return out;
}

export { songPath, artistPath };
export type { ArtistGroup, CatalogSong };
