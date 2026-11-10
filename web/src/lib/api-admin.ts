// Yönetici işlemleri: Gituar API'si (Cloudflare D1). Her istek Firebase kimlik kartıyla gider; yetkiyi API denetler.
import { API_URL } from "./site.ts";
import type { User } from "firebase/auth";

export interface PendingSong { id: string; artist: string; title: string; originalKey: string; content: string; addedBy: string | null; createdAt: number; artistSlug: string; slug: string }

async function call<T>(user: User, path: string, init: RequestInit = {}): Promise<T> {
  const res = await fetch(`${API_URL}${path}`, {
    ...init,
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${await user.getIdToken()}`, ...(init.headers ?? {}) },
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error((data as { error?: string }).error ?? `API ${res.status}`);
  return data as T;
}

/** true/false: API'nin cevabı; null: API'ye ulaşılamadı (ağ, CORS ya da sunucu hatası). */
export async function apiIsAdmin(user: User): Promise<boolean | null> {
  try { return (await call<{ isAdmin: boolean }>(user, "/v1/me")).isAdmin; } catch { return null; }
}

export async function listPending(user: User): Promise<PendingSong[]> {
  return (await call<{ songs: PendingSong[] }>(user, "/v1/admin/pending")).songs;
}

export async function setSongStatus(user: User, id: string, status: "approved" | "rejected"): Promise<void> {
  await call(user, `/v1/admin/songs/${encodeURIComponent(id)}/status`, { method: "POST", body: JSON.stringify({ status }) });
}

/** Şarkıyı veritabanından gerçekten siler (satır ve popülerlik kayıtları). */
export async function deleteSong(user: User, id: string): Promise<void> {
  await call(user, `/v1/songs/${encodeURIComponent(id)}`, { method: "DELETE" });
}

// ---------- Toplu içe aktarma (iOS JSONImportPreviewView / BulkRepertoireImportView ile aynı JSON) ----------

/** iOS ImportableSong: [{ songName, artist, originalKey, content, docId? }] */
export interface ImportableSong { songName?: string; artist?: string; originalKey?: string; content?: string; docId?: string }

export function validImport(s: ImportableSong): boolean {
  return Boolean(s.songName?.trim() && s.artist?.trim() && s.originalKey?.trim() && s.content?.trim());
}

/** Yöneticinin gönderdiği şarkı doğrudan yayında ("approved"). */
export async function importSong(user: User, s: ImportableSong, addedBy: string): Promise<void> {
  await call(user, "/v1/songs", {
    method: "POST",
    body: JSON.stringify({ artist: s.artist!.trim(), title: s.songName!.trim(), originalKey: s.originalKey!.trim(), content: s.content!, status: "approved", addedBy }),
  });
}

/** iOS BulkRepertoireEntry: [{ name, songIds: [...] }]. songIds öğesi şarkı kimliği, "sanatçı-slug/şarkı-slug" ya da "Sanatçı - Şarkı" olabilir. */
export interface BulkRepertoireEntry { name: string; songIds: string[] }

interface ListSong { id: string; artist: string; title: string; artistSlug: string; slug: string }

const norm = (s: string) => s.toLocaleLowerCase("tr-TR").replace(/[^\p{L}\p{N}]+/gu, " ").trim();

/** Kaynak gösterimlerini yayındaki şarkı kimliklerine çevirir; bulunamayanlar ayrıca döner. */
export async function resolveSongRefs(refs: string[]): Promise<{ ids: Map<string, string>; missing: string[] }> {
  const ids = new Map<string, string>();
  const plain = [...new Set(refs.map((r) => r.trim()).filter((r) => r && !r.includes("/") && !/\s-\s/.test(r)))];
  for (let i = 0; i < plain.length; i += 100) {
    const chunk = plain.slice(i, i + 100);
    const res = await fetch(`${API_URL}/v1/songs/batch?ids=${chunk.map(encodeURIComponent).join(",")}`);
    if (res.ok) for (const s of ((await res.json()) as { songs: ListSong[] }).songs) ids.set(s.id, s.id);
  }
  for (const raw of new Set(refs.map((r) => r.trim()).filter(Boolean))) {
    if (ids.has(raw)) continue;
    if (raw.includes("/")) {
      const [a, b] = raw.replace(/^\/?(akor\/)?/, "").replace(/\/$/, "").split("/");
      const res = await fetch(`${API_URL}/v1/songs/by-slug/${encodeURIComponent(a)}/${encodeURIComponent(b ?? "")}`);
      if (res.ok) ids.set(raw, ((await res.json()) as { song: ListSong }).song.id);
      continue;
    }
    const m = /^(.+?)\s-\s(.+)$/.exec(raw);
    if (!m) continue;
    const res = await fetch(`${API_URL}/v1/search?q=${encodeURIComponent(`${m[1]} ${m[2]}`)}&limit=20`);
    if (!res.ok) continue;
    const hit = ((await res.json()) as { songs: ListSong[] }).songs.find((s) => norm(s.artist) === norm(m[1]) && norm(s.title) === norm(m[2]));
    if (hit) ids.set(raw, hit.id);
  }
  return { ids, missing: [...new Set(refs.map((r) => r.trim()).filter((r) => r && !ids.has(r)))] };
}
