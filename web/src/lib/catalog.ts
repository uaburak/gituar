// Şarkı erişimi (sunucu tarafı). Şarkılar Gituar API'sinden (Cloudflare D1) alınır ve Worker belleğinde kısa süre
// tutulur: yeni yüklenen şarkı en geç TTL kadar sonra sitede görünür, silinen şarkı o kadar sonra 404 olur.
// Her istekte middleware `loadCatalog()` çağırır; sayfalar eşzamanlı `catalog()` ile okur.
import { groupByArtist, songPath, artistPath, type ArtistGroup } from "./paths.ts";
import type { CatalogSong } from "@shared/types";
import { API_URL } from "./site.ts";

/** API'den gelen şarkı: katalog alanlarına ek olarak popülerlik puanı ve güncellenme zamanı. */
export type ApiSong = CatalogSong & { score?: number; updatedAt?: string; ownerId?: string; rhythm?: string; arpeggio?: string; tempo?: number; meter?: string };

interface Catalog {
  songs: ApiSong[];
  artists: ArtistGroup[];
  artistBySlug: Map<string, ArtistGroup>;
  byId: Map<string, ApiSong>;
  bySlug: Map<string, ApiSong>;
}

const TTL_MS = 2 * 60 * 1000;
let cache: Catalog | null = null;
let loadedAt = 0;
let version = 0;
let inflight: Promise<void> | null = null;

async function fetchAll(): Promise<ApiSong[]> {
  const out: ApiSong[] = [];
  for (let offset = 0; ; offset += 1000) {
    // Cloudflare'in yerel önbelleğinde 5 dk: yeni başlayan Worker örnekleri listeyi API yerine önbellekten alır
    const res = await fetch(`${API_URL}/v1/export?limit=1000&offset=${offset}`, { cf: { cacheTtl: 300, cacheEverything: true } } as RequestInit);
    if (!res.ok) throw new Error(`Şarkı API'si yanıt vermedi (${res.status})`);
    const page = (await res.json()) as { songs: Record<string, unknown>[] };
    for (const s of page.songs) {
      out.push({
        id: s.id as string,
        artist: s.artist as string,
        songName: s.title as string,
        originalKey: s.originalKey as string,
        content: s.content as string,
        artistSlug: s.artistSlug as string,
        slug: s.slug as string,
        seq: s.createdAt as number,
        createdAt: new Date(s.createdAt as number).toISOString(),
        updatedAt: new Date(s.updatedAt as number).toISOString(),
        score: s.score as number,
        ...(s.addedBy ? { addedBy: s.addedBy as string } : {}),
        ...(s.ownerId ? { ownerId: s.ownerId as string } : {}),
        // Ritim bilgisi (API'de rhythm sütunu uygulandığında gelir; yoksa çalarken varsayılan desen)
        ...(s.rhythm ? { rhythm: s.rhythm as string } : {}),
        ...(s.arpeggio ? { arpeggio: s.arpeggio as string } : {}),
        ...(s.tempo ? { tempo: s.tempo as number } : {}),
        ...(s.meter ? { meter: s.meter as string } : {}),
      });
    }
    if (page.songs.length < 1000) break;
  }
  return out;
}

function build(songs: ApiSong[]): Catalog {
  const artists = groupByArtist(songs);
  return {
    songs,
    artists,
    artistBySlug: new Map(artists.map((a) => [a.slug, a])),
    byId: new Map(songs.map((s) => [s.id, s])),
    bySlug: new Map(songs.map((s) => [`${s.artistSlug}/${s.slug}`, s])),
  };
}

/**
 * Şarkı listesini hazırlar. Bellekte kopya varsa hemen döner (eskidiyse yenisi arka planda çekilir, ziyaretçi beklemez);
 * yalnızca hiç kopya yokken (Worker'ın ilk isteği) API'yi bekler. API hata verirse eski kopya kullanılmaya devam eder.
 * `waitUntil`: Cloudflare'de yanıt gittikten sonra da arka plan yenilemesinin bitmesini sağlar.
 */
export async function loadCatalog(waitUntil?: (p: Promise<unknown>) => void): Promise<void> {
  if (cache && Date.now() - loadedAt < TTL_MS) return;
  if (!inflight) {
    inflight = fetchAll()
      .then((songs) => {
        cache = build(songs);
        loadedAt = Date.now();
        version++;
      })
      .catch((e) => {
        if (!cache) throw e;
        console.warn("[catalog] yenilenemedi, eski kopya kullanılıyor:", (e as Error).message);
      })
      .finally(() => { inflight = null; });
  }
  if (cache) {
    // Eski kopyayla hemen yanıt ver; yenileme arka planda
    waitUntil?.(inflight);
    return;
  }
  await inflight;
}

export function catalog(): Catalog {
  if (!cache) throw new Error("catalog() loadCatalog() tamamlanmadan çağrıldı");
  return cache;
}

/** Her yenilemede artar; türetilmiş hesapların önbellekleri buna bakar. */
export function catalogVersion(): number {
  return version;
}

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
