// Firestore'dan snapshot.seq sonrası değişen şarkıları çeker ve catalog.deflate'i günceller.
// Yalnızca değişen dokümanlar okunur. Gerekli: GOOGLE_APPLICATION_CREDENTIALS
import { initializeApp, applicationDefault } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { applyDelta, readSnapshot, writeSnapshot } from "../src/catalog.ts";
import { snapshotPath } from "./_paths.mjs";

initializeApp({ credential: applicationDefault(), projectId: process.env.FIREBASE_PROJECT_ID ?? "koc-chords" });
const db = getFirestore();
const snapshot = readSnapshot(snapshotPath);
console.log(`Yerel snapshot seq=${snapshot.seq}, ${snapshot.songs.length} kayıt`);

const changes = [];
let lastSeq = snapshot.seq;
for (;;) {
  const page = await db.collection("songs").where("seq", ">", lastSeq).orderBy("seq").limit(500).get();
  if (page.empty) break;
  for (const doc of page.docs) {
    const d = doc.data();
    changes.push({
      id: doc.id,
      artist: d.artist ?? "",
      songName: d.songName ?? "",
      originalKey: d.originalKey ?? "",
      content: d.content ?? "",
      artistSlug: d.artistSlug ?? "",
      slug: d.slug ?? "",
      seq: d.seq,
      deleted: d.deleted === true,
      ...(d.addedBy ? { addedBy: d.addedBy } : {}),
      ...(d.createdAt?.toDate ? { createdAt: d.createdAt.toDate().toISOString() } : {}),
    });
    lastSeq = d.seq;
  }
  if (page.size < 500) break;
}
if (changes.length === 0) {
  console.log("Değişiklik yok.");
  process.exit(0);
}
const next = applyDelta(snapshot, changes);
writeSnapshot(snapshotPath, next);
console.log(`✅ ${changes.length} değişiklik uygulandı → seq=${next.seq}, ${next.count} şarkı`);
