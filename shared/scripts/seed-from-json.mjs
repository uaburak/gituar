// Tek seferlik: eski chords_data.json (Storage'daki tek dosya) → shared/catalog/catalog.deflate
// Kullanım: node shared/scripts/seed-from-json.mjs /yol/chords_data.json
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { assignSlugs, writeSnapshot } from "../src/catalog.ts";
import { snapshotPath } from "./_paths.mjs";

const input = process.argv[2];
if (!input) {
  console.error("Kullanım: node shared/scripts/seed-from-json.mjs <chords_data.json>");
  process.exit(1);
}
const legacy = JSON.parse(readFileSync(resolve(input), "utf8"));
if (!Array.isArray(legacy)) throw new Error("Beklenen biçim: şarkı dizisi");

let maxNumeric = 0;
for (const s of legacy) {
  const n = Number(s.docId);
  if (Number.isInteger(n) && n > maxNumeric) maxNumeric = n;
}
let nextSeq = maxNumeric;
const songs = legacy.map((s) => {
  const n = Number(s.docId);
  const seq = Number.isInteger(n) && n > 0 ? n : ++nextSeq;
  const song = {
    id: String(s.docId ?? seq),
    artist: String(s.artist ?? "").trim(),
    songName: String(s.songName ?? "").trim(),
    originalKey: String(s.originalKey ?? "").trim(),
    content: String(s.content ?? ""),
    artistSlug: "",
    slug: "",
    seq,
  };
  if (s.addedBy) song.addedBy = String(s.addedBy);
  if (typeof s.createdAt === "string") song.createdAt = s.createdAt;
  return song;
});
assignSlugs(songs);
songs.sort((a, b) => a.seq - b.seq);
const snapshot = { seq: nextSeq, count: songs.length, publishedAt: new Date().toISOString(), songs };
writeSnapshot(snapshotPath, snapshot);
console.log(`✅ ${songs.length} şarkı, seq=${snapshot.seq} → ${snapshotPath}`);
