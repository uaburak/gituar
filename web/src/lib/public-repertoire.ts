// Sunucu tarafı: herkese açık repertuarı adresinden bulur (Firestore REST; public-repertoires herkese açık okunur).
import { FIREBASE_CONFIG } from "./site.ts";

export interface PublicRepertoire { id: string; name: string; songIds: string[]; ownerId: string; ownerUsername: string; slug: string; createdAt: string }

type Fields = Record<string, { stringValue?: string; timestampValue?: string; arrayValue?: { values?: { stringValue?: string }[] } }>;

export async function findPublicRepertoire(username: string, slug: string): Promise<PublicRepertoire | null> {
  const key = FIREBASE_CONFIG.apiKey;
  if (!key) return null;
  const base = `https://firestore.googleapis.com/v1/projects/${FIREBASE_CONFIG.projectId}/databases/(default)/documents`;
  const eq = (field: string, value: string) => ({ fieldFilter: { field: { fieldPath: field }, op: "EQUAL", value: { stringValue: value } } });
  try {
    const rows: { document?: { name: string; fields?: Fields } }[] = await fetch(`${base}:runQuery?key=${key}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        structuredQuery: {
          from: [{ collectionId: "public-repertoires" }],
          where: { compositeFilter: { op: "AND", filters: [eq("ownerUsername", username), eq("slug", slug)] } },
          limit: 1,
        },
      }),
    }).then((r) => r.json());
    const doc = rows.find((r) => r.document)?.document;
    if (!doc) return null;
    const f = doc.fields ?? {};
    return {
      id: doc.name.split("/").pop()!,
      name: f.name?.stringValue ?? "",
      songIds: (f.songIds?.arrayValue?.values ?? []).map((v) => v.stringValue ?? "").filter(Boolean),
      ownerId: f.ownerId?.stringValue ?? "",
      ownerUsername: f.ownerUsername?.stringValue ?? username,
      slug: f.slug?.stringValue ?? slug,
      createdAt: f.createdAt?.timestampValue ?? "",
    };
  } catch (e) {
    console.warn("[public-repertoire] okunamadı:", (e as Error).message);
    return null;
  }
}

/** Kullanıcı adına göre herkese açık repertuarlar (en yeni önce). Profil sayfası kullanır. */
export async function listPublicRepertoiresByUsername(username: string): Promise<PublicRepertoire[]> {
  const key = FIREBASE_CONFIG.apiKey;
  if (!key) return [];
  const base = `https://firestore.googleapis.com/v1/projects/${FIREBASE_CONFIG.projectId}/databases/(default)/documents`;
  try {
    const rows: { document?: { name: string; fields?: Fields } }[] = await fetch(`${base}:runQuery?key=${key}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        structuredQuery: {
          from: [{ collectionId: "public-repertoires" }],
          where: { fieldFilter: { field: { fieldPath: "ownerUsername" }, op: "EQUAL", value: { stringValue: username } } },
          limit: 200,
        },
      }),
    }).then((r) => r.json());
    return rows
      .filter((r) => r.document)
      .map((r) => {
        const f = r.document!.fields ?? {};
        return {
          id: r.document!.name.split("/").pop()!,
          name: f.name?.stringValue ?? "",
          songIds: (f.songIds?.arrayValue?.values ?? []).map((v) => v.stringValue ?? "").filter(Boolean),
          ownerId: f.ownerId?.stringValue ?? "",
          ownerUsername: f.ownerUsername?.stringValue ?? username,
          slug: f.slug?.stringValue ?? "",
          createdAt: f.createdAt?.timestampValue ?? "",
        };
      })
      .filter((r) => r.name && r.slug)
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  } catch (e) {
    console.warn("[public-repertoire] profil okunamadı:", (e as Error).message);
    return [];
  }
}
