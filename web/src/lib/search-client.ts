// Tarayıcı araması: /search-index.json bir kez indirilir, Türkçe normalizasyonla anında filtrelenir.
import type { SearchIndexEntry } from "@shared/types";
import { searchSongs, turkeyNormalized } from "@shared/turkish";

let indexPromise: Promise<SearchIndexEntry[]> | null = null;

export function loadIndex(): Promise<SearchIndexEntry[]> {
  if (!indexPromise) {
    indexPromise = fetch("/search-index.json").then((r) => r.json() as Promise<SearchIndexEntry[]>);
  }
  return indexPromise;
}

export async function search(query: string, limit = 100): Promise<SearchIndexEntry[]> {
  const index = await loadIndex();
  const items = index.map((e) => ({ songName: e.s, artist: e.a, entry: e }));
  return searchSongs(items, query, true)
    .slice(0, limit)
    .map((m) => m.entry);
}

export interface ArtistHit { name: string; count: number; path: string }

/** Adı sorguyu içeren sanatçılar, akor sayısına göre. */
export async function searchArtists(query: string, limit = 5): Promise<ArtistHit[]> {
  const q = turkeyNormalized(query.trim());
  if (!q) return [];
  const index = await loadIndex();
  const counts = new Map<string, ArtistHit>();
  for (const e of index) {
    if (!turkeyNormalized(e.a).includes(q)) continue;
    const hit = counts.get(e.a) ?? { name: e.a, count: 0, path: e.p.split("/").slice(0, 3).join("/").replace("/akor/", "/sanatci/") + "/" };
    hit.count++;
    counts.set(e.a, hit);
  }
  return [...counts.values()].sort((a, b) => b.count - a.count).slice(0, limit);
}

export function rowHtml(e: SearchIndexEntry): string {
  return `<a class="row" href="${e.p}"><span class="row-body"><span class="row-title">${esc(e.s)}</span><span class="row-sub">${esc(e.a)}</span></span>${e.k ? `<span class="row-key">${esc(e.k)}</span>` : ""}</a>`;
}

export function artistRowHtml(a: ArtistHit): string {
  const initial = (a.name.trim()[0] ?? "?").toLocaleUpperCase("tr-TR");
  return `<a class="row" href="${a.path}"><span class="row-avatar" aria-hidden="true">${esc(initial)}</span><span class="row-body"><span class="row-title">${esc(a.name)}</span></span><span class="row-count">${a.count} akor</span></a>`;
}

export function esc(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}
