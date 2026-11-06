// Editörün seçimleri: admin hesapların herkese açık repertuarları (iOS ile aynı kaynak: metadata/admins + public-repertoires).
// Firebase SDK yüklemeden Firestore REST ile okunur; iki doküman da herkese açık.
import { FIREBASE_CONFIG } from "./site.ts";

export interface EditorPick { id: string; name: string; count: number; createdAt: string }

const BASE = `https://firestore.googleapis.com/v1/projects/${FIREBASE_CONFIG.projectId}/databases/(default)/documents`;
type Fields = Record<string, { stringValue?: string; booleanValue?: boolean; timestampValue?: string; arrayValue?: { values?: { stringValue?: string }[] } }>;
const str = (f: Fields, k: string) => f[k]?.stringValue ?? "";
const arr = (f: Fields, k: string) => (f[k]?.arrayValue?.values ?? []).map((v) => v.stringValue ?? "").filter(Boolean);

let cache: Promise<EditorPick[]> | null = null;

export function editorPicks(): Promise<EditorPick[]> {
  if (!FIREBASE_CONFIG.apiKey) return Promise.resolve([]);
  if (cache) return cache;
  cache = (async () => {
    try {
      const sessionKey = "gituar-editor-picks";
      try {
        const raw = sessionStorage.getItem(sessionKey);
        if (raw) { const c = JSON.parse(raw) as { t: number; picks: EditorPick[] }; if (Date.now() - c.t < 10 * 60 * 1000) return c.picks; }
      } catch {}
      const admins = await fetch(`${BASE}/metadata/admins?key=${FIREBASE_CONFIG.apiKey}`).then((r) => r.json());
      const uids = arr((admins.fields ?? {}) as Fields, "uids").slice(0, 30);
      if (!uids.length) return [];
      const query = {
        structuredQuery: {
          from: [{ collectionId: "public-repertoires" }],
          where: { fieldFilter: { field: { fieldPath: "ownerId" }, op: "IN", value: { arrayValue: { values: uids.map((u) => ({ stringValue: u })) } } } },
          limit: 60,
        },
      };
      const rows: { document?: { name: string; fields?: Fields } }[] = await fetch(`${BASE}:runQuery?key=${FIREBASE_CONFIG.apiKey}`, {
        method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(query),
      }).then((r) => r.json());
      const picks = rows
        .filter((r) => r.document)
        .map((r) => {
          const f = r.document!.fields ?? {};
          return { id: r.document!.name.split("/").pop()!, name: str(f, "name"), count: arr(f, "songIds").length, createdAt: f.createdAt?.timestampValue ?? "" };
        })
        .filter((p) => p.name && p.count > 0)
        .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
      try { sessionStorage.setItem(sessionKey, JSON.stringify({ t: Date.now(), picks })); } catch {}
      return picks;
    } catch (e) {
      console.warn("Editörün seçimleri yüklenemedi", e);
      return [];
    }
  })();
  return cache;
}

export function pickCardHtml(p: EditorPick, esc: (s: string) => string): string {
  return `<a class="card pick" href="/repertuar/?id=${esc(p.id)}"><span class="pick-tile" aria-hidden="true">${esc(p.name.trim().charAt(0).toLocaleUpperCase("tr-TR"))}</span><span class="pick-body"><span class="pick-title">${esc(p.name)}</span><span class="muted small">${p.count} şarkı · Editör repertuarı</span></span><span class="pick-arrow" aria-hidden="true">›</span></a>`;
}
