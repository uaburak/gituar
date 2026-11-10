// Kullanıcının kendi şarkıları (iOS Şarkılarım ile aynı uçlar): Gituar API'si, Firebase kimlik kartıyla.
import { API_URL } from "./site.ts";
import type { User } from "firebase/auth";

export type SongStatus = "draft" | "pending" | "approved" | "rejected";

export interface MySong {
  id: string;
  artist: string;
  title: string;
  originalKey: string;
  content: string;
  status: SongStatus;
  artistSlug: string;
  slug: string;
  addedBy: string | null;
  updatedAt: number;
}

export interface SongInput {
  artist: string;
  title: string;
  originalKey: string;
  content: string;
  /** "draft" | "pending" (yöneticide "approved" da) */
  status: SongStatus;
  addedBy?: string;
}

async function call<T>(user: User, path: string, init: RequestInit = {}): Promise<T> {
  const res = await fetch(`${API_URL}${path}`, {
    ...init,
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${await user.getIdToken()}`, ...(init.headers ?? {}) },
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error((data as { error?: string }).error ?? `Sunucu hatası (${res.status})`);
  return data as T;
}

export async function listMySongs(user: User): Promise<MySong[]> {
  return (await call<{ songs: MySong[] }>(user, "/v1/me/songs")).songs;
}

export async function createSong(user: User, input: SongInput): Promise<MySong> {
  return (await call<{ song: MySong }>(user, "/v1/songs", { method: "POST", body: JSON.stringify(input) })).song;
}

export async function updateSong(user: User, id: string, input: Partial<SongInput>): Promise<MySong> {
  return (await call<{ song: MySong }>(user, `/v1/songs/${encodeURIComponent(id)}`, { method: "PATCH", body: JSON.stringify(input) })).song;
}

export async function removeSong(user: User, id: string): Promise<void> {
  await call(user, `/v1/songs/${encodeURIComponent(id)}`, { method: "DELETE" });
}

export const STATUS_LABEL: Record<SongStatus, string> = { approved: "Yayında", pending: "Onay Bekliyor", draft: "Taslak", rejected: "Reddedildi" };
