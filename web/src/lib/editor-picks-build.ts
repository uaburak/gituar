// Editörün seçimleri, build zamanı: sayfa sunucuda dolu üretilsin diye aynı REST sorgusu Node'da çalışır.
// Ağ yoksa boş döner; sayfa o durumda tarayıcıda yükler ve dizine girmez.
import { FIREBASE_CONFIG } from "./site.ts";

export interface BuildPick { id: string; name: string; songIds: string[]; createdAt: string }

type Fields = Record<string, { stringValue?: string; timestampValue?: string; arrayValue?: { values?: { stringValue?: string }[] } }>;
const arr = (f: Fields, k: string) => (f[k]?.arrayValue?.values ?? []).map((v) => v.stringValue ?? "").filter(Boolean);

let cache: Promise<BuildPick[]> | null = null;

export function buildEditorPicks(): Promise<BuildPick[]> {
  if (cache) return cache;
  cache = (async () => {
    const key = FIREBASE_CONFIG.apiKey;
    if (!key) return [];
    const base = `https://firestore.googleapis.com/v1/projects/${FIREBASE_CONFIG.projectId}/databases/(default)/documents`;
    try {
      const admins = await fetch(`${base}/metadata/admins?key=${key}`).then((r) => r.json());
      const uids = arr((admins.fields ?? {}) as Fields, "uids").slice(0, 30);
      if (!uids.length) return [];
      const rows: { document?: { name: string; fields?: Fields } }[] = await fetch(`${base}:runQuery?key=${key}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          structuredQuery: {
            from: [{ collectionId: "public-repertoires" }],
            where: { fieldFilter: { field: { fieldPath: "ownerId" }, op: "IN", value: { arrayValue: { values: uids.map((u) => ({ stringValue: u })) } } } },
            limit: 60,
          },
        }),
      }).then((r) => r.json());
      return rows
        .filter((r) => r.document)
        .map((r) => {
          const f = r.document!.fields ?? {};
          return { id: r.document!.name.split("/").pop()!, name: f.name?.stringValue ?? "", songIds: arr(f, "songIds"), createdAt: f.createdAt?.timestampValue ?? "" };
        })
        .filter((p) => p.name && p.songIds.length > 0)
        .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
    } catch (e) {
      console.warn("[editor-picks] build sırasında okunamadı:", (e as Error).message);
      return [];
    }
  })();
  return cache;
}

let popCache: Promise<Map<string, number>> | null = null;

/** Şarkı id → kaç herkese açık repertuarda geçtiği. iOS'taki "En Çok Eklenenler" ile aynı ölçüt. */
export function buildPopularity(): Promise<Map<string, number>> {
  if (popCache) return popCache;
  popCache = (async () => {
    const counts = new Map<string, number>();
    const key = FIREBASE_CONFIG.apiKey;
    if (!key) return counts;
    const base = `https://firestore.googleapis.com/v1/projects/${FIREBASE_CONFIG.projectId}/databases/(default)/documents/public-repertoires`;
    try {
      let token = "";
      for (let page = 0; page < 50; page++) {
        const url = `${base}?key=${key}&pageSize=300&mask.fieldPaths=songIds${token ? `&pageToken=${encodeURIComponent(token)}` : ""}`;
        const res: { documents?: { fields?: Fields }[]; nextPageToken?: string } = await fetch(url).then((r) => r.json());
        for (const d of res.documents ?? []) for (const id of new Set(arr(d.fields ?? {}, "songIds"))) counts.set(id, (counts.get(id) ?? 0) + 1);
        if (!res.nextPageToken) break;
        token = res.nextPageToken;
      }
    } catch (e) {
      console.warn("[popularity] build sırasında okunamadı:", (e as Error).message);
    }
    return counts;
  })();
  return popCache;
}
