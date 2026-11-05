// Tek seferlik: catalog.deflate → Firestore songs/{id} + catalog/meta. 500'lük batch'ler.
// Gerekli: GOOGLE_APPLICATION_CREDENTIALS=<service-account.json>  (Firebase Console → Project settings → Service accounts)
// Kullanım: node shared/scripts/import-catalog.mjs [--dry-run]
import { initializeApp, applicationDefault } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { readSnapshot } from "../src/catalog.ts";
import { snapshotPath } from "./_paths.mjs";

const dryRun = process.argv.includes("--dry-run");
const snapshot = readSnapshot(snapshotPath);
console.log(`Snapshot: ${snapshot.songs.length} şarkı, seq=${snapshot.seq}`);
if (dryRun) {
  console.log("--dry-run: Firestore'a yazılmadı.");
  process.exit(0);
}

initializeApp({ credential: applicationDefault(), projectId: process.env.FIREBASE_PROJECT_ID ?? "koc-chords" });
const db = getFirestore();
const BATCH = 450;
let written = 0;
for (let i = 0; i < snapshot.songs.length; i += BATCH) {
  const batch = db.batch();
  for (const s of snapshot.songs.slice(i, i + BATCH)) {
    const ref = db.collection("songs").doc(s.id);
    batch.set(ref, {
      artist: s.artist,
      songName: s.songName,
      originalKey: s.originalKey,
      content: s.content,
      artistSlug: s.artistSlug,
      slug: s.slug,
      status: "approved",
      seq: s.seq,
      deleted: s.deleted === true,
      addedBy: s.addedBy ?? null,
      createdAt: s.createdAt ? new Date(s.createdAt) : FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
  written += Math.min(BATCH, snapshot.songs.length - i);
  console.log(`  ${written}/${snapshot.songs.length}`);
}
await db.collection("catalog").doc("meta").set({ seq: snapshot.seq, count: snapshot.count, publishedAt: new Date() });
console.log("✅ Import tamam. catalog/meta.seq =", snapshot.seq);
