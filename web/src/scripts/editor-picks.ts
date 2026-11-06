// Ana sayfa "Editörün seçimleri": admin hesapların herkese açık repertuarları (iOS ile aynı).
// Firebase SDK yüklemeden Firestore REST ile okunur; metadata/admins ve public-repertoires herkese açık.
import { FIREBASE_CONFIG } from "../lib/site.ts";
import { esc } from "../lib/search-client.ts";

const section = document.getElementById("editor");
const grid = document.getElementById("editor-picks");
const BASE = `https://firestore.googleapis.com/v1/projects/${FIREBASE_CONFIG.projectId}/databases/(default)/documents`;

type Fields = Record<string, { stringValue?: string; booleanValue?: boolean; timestampValue?: string; arrayValue?: { values?: { stringValue?: string }[] } }>;
const str = (f: Fields, k: string) => f[k]?.stringValue ?? "";
const arr = (f: Fields, k: string) => (f[k]?.arrayValue?.values ?? []).map((v) => v.stringValue ?? "").filter(Boolean);

(async () => {
  if (!section || !grid || !FIREBASE_CONFIG.apiKey) return;
  try {
    const admins = await fetch(`${BASE}/metadata/admins?key=${FIREBASE_CONFIG.apiKey}`).then((r) => r.json());
    const uids = arr((admins.fields ?? {}) as Fields, "uids").slice(0, 30);
    if (!uids.length) return;
    const query = {
      structuredQuery: {
        from: [{ collectionId: "public-repertoires" }],
        where: { fieldFilter: { field: { fieldPath: "ownerId" }, op: "IN", value: { arrayValue: { values: uids.map((u) => ({ stringValue: u })) } } } },
        limit: 30,
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
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
      .slice(0, 9);
    if (!picks.length) return;
    grid.innerHTML = picks
      .map((p) => `<a class="card pick" href="/repertuar/?id=${esc(p.id)}"><span class="pick-tile" aria-hidden="true">${esc(p.name.trim().charAt(0).toLocaleUpperCase("tr-TR"))}</span><span class="pick-body"><span class="pick-title">${esc(p.name)}</span><span class="muted small">${p.count} şarkı · Editör repertuarı</span></span><span class="pick-arrow" aria-hidden="true">›</span></a>`)
      .join("");
    section.hidden = false;
  } catch (e) {
    console.warn("Editörün seçimleri yüklenemedi", e);
  }
})();
