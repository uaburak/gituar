// Build zamanı katalog erişimi (yalnızca sunucu tarafı / Astro build). Snapshot bir kez açılır ve bellekte tutulur.
import { fileURLToPath } from "node:url";
import { readSnapshot, groupByArtist, buildSearchIndex, songPath, artistPath, type ArtistGroup } from "@shared/catalog";
import type { CatalogSong, CatalogSnapshot, SearchIndexEntry } from "@shared/types";

const SNAPSHOT_PATH = fileURLToPath(new URL("../../../shared/catalog/catalog.deflate", import.meta.url));

interface Catalog {
  snapshot: CatalogSnapshot;
  songs: CatalogSong[];
  artists: ArtistGroup[];
  artistBySlug: Map<string, ArtistGroup>;
  byId: Map<string, CatalogSong>;
}

let cache: Catalog | null = null;

export function catalog(): Catalog {
  if (cache) return cache;
  const snapshot = readSnapshot(SNAPSHOT_PATH);
  let songs = snapshot.songs.filter((s) => !s.deleted);
  const limit = Number(process.env.CATALOG_LIMIT ?? 0);
  if (limit > 0) songs = songs.slice(-limit);
  const artists = groupByArtist(songs);
  cache = {
    snapshot,
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

export function searchIndex(): SearchIndexEntry[] {
  return buildSearchIndex(catalog().songs);
}

export { songPath, artistPath };
export type { ArtistGroup, CatalogSong };
