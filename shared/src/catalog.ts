// Katalog snapshot'ı (catalog.deflate) okuma/yazma ve türetilmiş listeler. Yalnızca Node'da (build ve scriptler).
import { deflateRawSync, inflateRawSync } from "node:zlib";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";
import type { CatalogSnapshot, CatalogSong, SearchIndexEntry } from "./types.ts";
import { compareTurkish, slugify } from "./turkish.ts";

export function readSnapshot(path: string): CatalogSnapshot {
  const json = inflateRawSync(readFileSync(path)).toString("utf8");
  return JSON.parse(json) as CatalogSnapshot;
}

export function writeSnapshot(path: string, snapshot: CatalogSnapshot): void {
  mkdirSync(dirname(path), { recursive: true });
  const buf = deflateRawSync(Buffer.from(JSON.stringify(snapshot)), { level: 9 });
  writeFileSync(path, buf);
}

export function songPath(song: Pick<CatalogSong, "artistSlug" | "slug">): string {
  return `/akor/${song.artistSlug}/${song.slug}/`;
}

export function artistPath(artistSlug: string): string {
  return `/sanatci/${artistSlug}/`;
}

export interface ArtistGroup {
  name: string;
  slug: string;
  songs: CatalogSong[];
}

/** Silinmemiş şarkıları sanatçıya göre gruplar; sanatçılar ve şarkılar Türkçe sıralıdır. */
export function groupByArtist(songs: readonly CatalogSong[]): ArtistGroup[] {
  const map = new Map<string, ArtistGroup>();
  for (const s of songs) {
    if (s.deleted) continue;
    let g = map.get(s.artistSlug);
    if (!g) {
      g = { name: s.artist.trim(), slug: s.artistSlug, songs: [] };
      map.set(s.artistSlug, g);
    }
    g.songs.push(s);
  }
  const groups = [...map.values()];
  for (const g of groups) g.songs.sort((a, b) => compareTurkish(a.songName, b.songName));
  groups.sort((a, b) => compareTurkish(a.name, b.name));
  return groups;
}

export function buildSearchIndex(songs: readonly CatalogSong[]): SearchIndexEntry[] {
  return songs
    .filter((s) => !s.deleted)
    .map((s) => ({ i: s.id, a: s.artist.trim(), s: s.songName.trim(), k: s.originalKey, p: songPath(s) }));
}

/**
 * Her şarkıya (artistSlug, slug) verir; aynı sanatçıda aynı slug tekrar ederse -2, -3 eklenir.
 * Slug'lar bir kez verildikten sonra değişmez (URL kalıcılığı): mevcut slug'ı olan kayıtlara dokunmaz.
 */
export function assignSlugs(songs: CatalogSong[]): void {
  const used = new Set<string>();
  for (const s of songs) {
    if (s.artistSlug && s.slug) used.add(`${s.artistSlug}/${s.slug}`);
  }
  for (const s of songs) {
    if (s.artistSlug && s.slug) continue;
    const artistSlug = slugify(s.artist);
    const base = slugify(s.songName);
    let slug = base;
    let n = 2;
    while (used.has(`${artistSlug}/${slug}`)) slug = `${base}-${n++}`;
    used.add(`${artistSlug}/${slug}`);
    s.artistSlug = artistSlug;
    s.slug = slug;
  }
}

/** Snapshot'a fark uygular: aynı id'li kayıt üzerine yazılır, deleted olanlar kalır (fark taşısın diye). */
export function applyDelta(snapshot: CatalogSnapshot, changes: readonly CatalogSong[]): CatalogSnapshot {
  const byId = new Map(snapshot.songs.map((s) => [s.id, s]));
  let seq = snapshot.seq;
  for (const c of changes) {
    byId.set(c.id, c);
    if (c.seq > seq) seq = c.seq;
  }
  // Silinen şarkının içeriği tutulmaz: yalnızca id + seq + deleted kalır (cihazlar silmeyi öğrensin diye)
  const songs = [...byId.values()]
    .map((s) => (s.deleted ? { id: s.id, artist: "", songName: "", originalKey: "", content: "", artistSlug: "", slug: "", seq: s.seq, deleted: true } : s))
    .sort((a, b) => a.seq - b.seq);
  return { seq, count: songs.filter((s) => !s.deleted).length, publishedAt: new Date().toISOString(), songs };
}
