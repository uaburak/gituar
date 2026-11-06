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

export async function apiIsAdmin(user: User): Promise<boolean> {
  try { return (await call<{ isAdmin: boolean }>(user, "/v1/me")).isAdmin; } catch { return false; }
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
