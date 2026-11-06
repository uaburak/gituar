// Web derlemesinden önce: snapshot.seq sonrası değişen şarkıları (yeni, düzenlenen, silinen) Firestore REST ile çeker
// ve catalog.deflate'i günceller. Kimlik bilgisi gerekmez: songs koleksiyonu herkese okunur, web API anahtarı yeter.
// Ağ yoksa ya da anahtar tanımlı değilse uyarı verir ve mevcut snapshot ile devam eder (derleme bozulmaz).
import { inflateRawSync, deflateRawSync } from "node:zlib";
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";
import { snapshotPath, repoRoot } from "./_paths.mjs";

function envKey() {
  if (process.env.PUBLIC_FIREBASE_API_KEY) return process.env.PUBLIC_FIREBASE_API_KEY;
  const envFile = resolve(repoRoot, "web/.env");
  if (!existsSync(envFile)) return "";
  const m = /^PUBLIC_FIREBASE_API_KEY=(.*)$/m.exec(readFileSync(envFile, "utf8"));
  return m ? m[1].trim() : "";
}

const key = envKey();
const project = process.env.PUBLIC_FIREBASE_PROJECT_ID || "koc-chords";
if (!key) {
  console.warn("[catalog] PUBLIC_FIREBASE_API_KEY yok; katalog güncellenmeden derleniyor.");
  process.exit(0);
}

const val = (f) => {
  if (!f) return undefined;
  if ("stringValue" in f) return f.stringValue;
  if ("integerValue" in f) return Number(f.integerValue);
  if ("doubleValue" in f) return Number(f.doubleValue);
  if ("booleanValue" in f) return f.booleanValue;
  if ("timestampValue" in f) return f.timestampValue;
  return undefined;
};

const snapshot = JSON.parse(inflateRawSync(readFileSync(snapshotPath)).toString("utf8"));
const url = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents:runQuery?key=${key}`;
const changes = [];
let lastSeq = snapshot.seq;

try {
  for (let page = 0; page < 100; page++) {
    const body = {
      structuredQuery: {
        from: [{ collectionId: "songs" }],
        where: { fieldFilter: { field: { fieldPath: "seq" }, op: "GREATER_THAN", value: { integerValue: String(lastSeq) } } },
        orderBy: [{ field: { fieldPath: "seq" }, direction: "ASCENDING" }],
        limit: 500,
      },
    };
    const res = await fetch(url, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
    if (!res.ok) throw new Error(`HTTP ${res.status}: ${(await res.text()).slice(0, 200)}`);
    const rows = (await res.json()).filter((r) => r.document);
    for (const r of rows) {
      const f = r.document.fields ?? {};
      const seq = val(f.seq);
      if (typeof seq !== "number") continue;
      const addedBy = val(f.addedBy);
      const createdAt = val(f.createdAt);
      changes.push({
        id: r.document.name.split("/").pop(),
        artist: val(f.artist) ?? "",
        songName: val(f.songName) ?? "",
        originalKey: val(f.originalKey) ?? "",
        content: val(f.content) ?? "",
        artistSlug: val(f.artistSlug) ?? "",
        slug: val(f.slug) ?? "",
        seq,
        deleted: val(f.deleted) === true,
        ...(addedBy ? { addedBy } : {}),
        ...(createdAt ? { createdAt } : {}),
      });
      lastSeq = Math.max(lastSeq, seq);
    }
    if (rows.length < 500) break;
  }
} catch (e) {
  console.warn(`[catalog] Firestore'dan fark çekilemedi (${e.message}); mevcut snapshot ile derleniyor.`);
  process.exit(0);
}

if (changes.length === 0) {
  console.log(`[catalog] Değişiklik yok (seq=${snapshot.seq}).`);
  process.exit(0);
}

// shared/src/catalog.ts applyDelta ile aynı mantık
const byId = new Map(snapshot.songs.map((s) => [s.id, s]));
let seq = snapshot.seq;
for (const c of changes) {
  byId.set(c.id, c);
  if (c.seq > seq) seq = c.seq;
}
// Silinen şarkıların içeriği hiçbir kopyada kalmaz: yalnızca id + seq + deleted
const tombstone = (s) => ({ id: s.id, artist: "", songName: "", originalKey: "", content: "", artistSlug: "", slug: "", seq: s.seq, deleted: true });
const songs = [...byId.values()].map((s) => (s.deleted ? tombstone(s) : s)).sort((a, b) => a.seq - b.seq);
const next = { seq, count: songs.filter((s) => !s.deleted).length, publishedAt: new Date().toISOString(), songs };
writeFileSync(snapshotPath, deflateRawSync(Buffer.from(JSON.stringify(next)), { level: 9 }));
const removed = changes.filter((c) => c.deleted).length;
console.log(`[catalog] ${changes.length} değişiklik uygulandı (${removed} silinen) → seq=${seq}`);
