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

