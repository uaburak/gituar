// Tarayıcı tarafı şarkı erişimi: arama, toplu şarkı, tek şarkı — hepsi Gituar API'sinden (Cloudflare D1).
// Bütün şarkıları içeren bir dosya indirilmez; her istek yalnızca gereken kadar veri getirir.
import { API_URL } from "./site.ts";

/** Listelerde kullanılan kısa şarkı kaydı (eski arama dizini alanlarıyla aynı adlar). */
export interface SongEntry {
  /** id */ i: string;
  /** sanatçı */ a: string;
  /** şarkı adı */ s: string;
  /** ton */ k: string;
  /** sayfa yolu */ p: string;
}

interface ApiListSong { id: string; artist: string; title: string; originalKey: string; artistSlug: string; slug: string }

export function toEntry(s: ApiListSong): SongEntry {
  return { i: s.id, a: s.artist, s: s.title, k: s.originalKey, p: `/akor/${s.artistSlug}/${s.slug}/` };
}

async function get<T>(path: string): Promise<T> {
  const res = await fetch(`${API_URL}${path}`);
  if (!res.ok) throw new Error(`API ${res.status}`);
  return res.json() as Promise<T>;
}

export interface ArtistHit { name: string; count: number; path: string }

interface SearchResult { songs: SongEntry[]; artists: ArtistHit[] }
const cache = new Map<string, Promise<SearchResult>>();

/** Şarkı ve sanatçı araması (Türkçe karakter duyarsız, kelime parçasıyla). */
export function searchAll(query: string, limit = 50): Promise<SearchResult> {
  const q = query.trim();
  if (!q) return Promise.resolve({ songs: [], artists: [] });
  const key = `${q}|${limit}`;
  if (!cache.has(key)) {
    cache.set(
      key,
      get<{ songs: ApiListSong[]; artists: { slug: string; name: string; songs: number }[] }>(`/v1/search?q=${encodeURIComponent(q)}&limit=${limit}`)
        .then((r) => ({
          songs: r.songs.map(toEntry),
          artists: r.artists.map((a) => ({ name: a.name, count: a.songs, path: `/sanatci/${a.slug}/` })),
        }))
        .catch((e) => { cache.delete(key); throw e; }),
    );
  }
  return cache.get(key)!;
}

export async function search(query: string, limit = 100): Promise<SongEntry[]> {
  return (await searchAll(query, limit)).songs;
}

export async function searchArtists(query: string, limit = 5): Promise<ArtistHit[]> {
  return (await searchAll(query)).artists.slice(0, limit);
}

/** Repertuarlar için: id listesinden şarkılar (yayında olmayanlar dönmez), verilen sırayla. */
export async function songsByIds(ids: string[]): Promise<SongEntry[]> {
  const out = new Map<string, SongEntry>();
  for (let i = 0; i < ids.length; i += 100) {
    const chunk = ids.slice(i, i + 100);
    const r = await get<{ songs: ApiListSong[] }>(`/v1/songs/batch?ids=${chunk.map(encodeURIComponent).join(",")}`);
    for (const s of r.songs) out.set(s.id, toEntry(s));
  }
  return ids.map((id) => out.get(id)).filter((e): e is SongEntry => Boolean(e));
}

/** Şarkı yayında mı? (silinmiş ya da yayından kalkmışsa false) */
export async function songExists(id: string): Promise<boolean> {
  const res = await fetch(`${API_URL}/v1/songs/${encodeURIComponent(id)}`);
  if (res.status === 404) return false;
  return true;
}

export async function newestSongs(limit = 100): Promise<SongEntry[]> {
  return (await get<{ songs: ApiListSong[] }>(`/v1/songs?sort=new&limit=${limit}`)).songs.map(toEntry);
}

/** Repertuarım düzenindeki şarkı satırı: `<ul class="rp-list">` içine `<li>`. */
export function rowHtml(e: SongEntry): string {
  return `<li><a class="row" href="${e.p}" title="${esc(e.a)} - ${esc(e.s)} akor"><span class="rp-badge" aria-hidden="true">A</span><span class="rp-text"><span class="row-artist">${esc(e.a)} - </span><span class="row-title">${esc(e.s)}</span></span></a></li>`;
}

/** Repertuarım düzenindeki sanatçı satırı ("S" rozeti). */
export function artistRowHtml(a: ArtistHit): string {
  return `<li><a class="row" href="${a.path}" title="${esc(a.name)} akorları"><span class="rp-badge rp-badge-artist" aria-hidden="true">S</span><span class="rp-text"><span class="row-title">${esc(a.name)}</span><span class="row-note"> · ${a.count} şarkı</span></span></a></li>`;
}

export function esc(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}
