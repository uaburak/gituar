// Build zamanı şarkı erişimi (yalnızca Astro build). Şarkılar Gituar API'sinden (Cloudflare D1) derleme öncesi
// scripts/fetch-songs.mjs ile .cache/songs.json'a alınır; burada bir kez okunup bellekte tutulur.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { groupByArtist, songPath, artistPath, type ArtistGroup } from "@shared/catalog";
import type { CatalogSong } from "@shared/types";

const SONGS_PATH = fileURLToPath(new URL("../../.cache/songs.json", import.meta.url));

/** API'den gelen şarkı: katalog alanlarına ek olarak popülerlik puanı ve güncellenme zamanı. */
export type ApiSong = CatalogSong & { score?: number; updatedAt?: string };

interface Catalog {
  songs: ApiSong[];
  artists: ArtistGroup[];
  artistBySlug: Map<string, ArtistGroup>;
  byId: Map<string, CatalogSong>;
}

let cache: Catalog | null = null;

export function catalog(): Catalog {
  if (cache) return cache;
  let songs: ApiSong[];
  try {
    songs = JSON.parse(readFileSync(SONGS_PATH, "utf8")) as ApiSong[];
  } catch {
    throw new Error("Şarkılar yok: önce `node scripts/fetch-songs.mjs` çalıştır (npm run build bunu kendisi yapar).");
  }
  const limit = Number(process.env.CATALOG_LIMIT ?? 0);
  if (limit > 0) songs = songs.slice(-limit);
  const artists = groupByArtist(songs);
  cache = {
    songs,
    artists,
    artistBySlug: new Map(artists.map((a) => [a.slug, a])),
    byId: new Map(songs.map((s) => [s.id, s])),
  };
  return cache;
}

export function newestSongs(n: number): CatalogSong[] {
  return [...catalog().songs].sort((a, b) => b.seq - a.seq).slice(0, n);
}

export function topArtists(n: number): ArtistGroup[] {
  return [...catalog().artists].sort((a, b) => b.songs.length - a.songs.length).slice(0, n);
}

/** Aynı tondaki başka sanatçıların şarkıları; seq'e bağlı deterministik seçim (her build aynı sonucu verir). */
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
