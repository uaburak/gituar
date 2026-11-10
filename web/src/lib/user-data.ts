// Kullanıcıya özel veriler (iOS ile aynı Firestore alanları):
//  users/{uid}                      profil (firstName, lastName, username, email, photoUrl, createdAt) + blockedUsers
//  users/{uid}/preferences/{songId} şarkı tercihi: { songId, selectedKeyRoot, capoFret, note }
// Firebase SDK firebase-client.ts üzerinden, yalnızca gerektiğinde yüklenir.
import { fb } from "./firebase-client.ts";

export interface Profile {
  uid: string;
  firstName: string;
  lastName: string;
  username: string;
  email?: string;
  blockedUsers: string[];
  isAdmin: boolean;
}

const BLOCKED_KEY = "gituar-blocked";

async function need() {
  const f = await fb();
  if (!f) throw new Error("Firebase hazır değil");
  return f;
}

/** Profil dökümanı; yoksa null (kullanıcı adı henüz seçilmemiş). */
export async function getProfile(uid: string): Promise<Profile | null> {
  const f = await need();
  const snap = await f.fsMod.getDoc(f.fsMod.doc(f.db, "users", uid));
  if (!snap.exists()) return null;
  const x = snap.data();
  const blocked = Array.isArray(x.blockedUsers) ? (x.blockedUsers as string[]) : [];
  rememberBlocked(blocked);
  return {
    uid,
    firstName: String(x.firstName ?? ""),
    lastName: String(x.lastName ?? ""),
    username: String(x.username ?? ""),
    email: typeof x.email === "string" ? x.email : undefined,
    blockedUsers: blocked,
    isAdmin: x.isAdmin === true,
  };
}

/** Kullanıcı adı kuralı iOS CompleteProfileView ile aynı: küçük harf, rakam ve alt çizgi, en az 3 karakter. */
export function cleanUsername(value: string): string {
  return value.toLocaleLowerCase("tr-TR").replace(/[^a-z0-9_]/g, "");
}

export async function isUsernameTaken(username: string, exceptUid?: string): Promise<boolean> {
  const f = await need();
  const snap = await f.fsMod.getDocs(
    f.fsMod.query(f.fsMod.collection(f.db, "users"), f.fsMod.where("username", "==", cleanUsername(username)), f.fsMod.limit(2)),
  );
  return snap.docs.some((d) => d.id !== exceptUid);
}

/** Profili kaydeder (merge: isAdmin, proGrant, blockedUsers gibi alanlar korunur). Yeni profilde iOS gibi 4 varsayılan repertuar açılır. */
export async function saveProfile(uid: string, p: { firstName: string; lastName: string; username: string; email?: string | null; photoUrl?: string | null }): Promise<void> {
  const f = await need();
  const ref = f.fsMod.doc(f.db, "users", uid);
  const existed = (await f.fsMod.getDoc(ref)).exists();
  const data: Record<string, unknown> = {
    uid,
    firstName: p.firstName.trim(),
    lastName: p.lastName.trim(),
    username: cleanUsername(p.username),
  };
  if (p.email) data.email = p.email;
  if (p.photoUrl) data.photoUrl = p.photoUrl;
  if (!existed) data.createdAt = f.fsMod.Timestamp.now();
  await f.fsMod.setDoc(ref, data, { merge: true });
  if (!existed) {
    // iOS ChordViewModel.createDefaultRepertoires ile aynı adlar
    for (const [i, name] of ["Favoriler", "Sahne", "Sahil", "Çalışılacak"].entries()) {
      const r = f.fsMod.doc(f.fsMod.collection(f.db, "users", uid, "repertoires"));
      await f.fsMod.setDoc(r, { name, songIds: [], ownerId: uid, isPublic: false, createdAt: f.fsMod.Timestamp.fromMillis(Date.now() - i * 1000) }).catch(() => {});
    }
  }
}

/** Başka bir kullanıcının kullanıcı adı (users okumak için giriş gerekir; olmazsa null). */
export async function usernameOf(uid: string): Promise<string | null> {
  try {
    const f = await need();
    const snap = await f.fsMod.getDoc(f.fsMod.doc(f.db, "users", uid));
    const name = snap.data()?.username;
    return typeof name === "string" && name ? name : null;
  } catch {
    return null;
  }
}

// ---------- Engelleme (App Store 1.2; iOS ile aynı alan: users/{uid}.blockedUsers) ----------

function rememberBlocked(ids: string[]) {
  try { localStorage.setItem(BLOCKED_KEY, JSON.stringify(ids)); } catch {}
}

/** Bu tarayıcıda bilinen engelli kullanıcılar (girişte Firestore'dan yenilenir); listeleri süzmek için. */
export function blockedLocal(): Set<string> {
  try { return new Set(JSON.parse(localStorage.getItem(BLOCKED_KEY) ?? "[]") as string[]); } catch { return new Set(); }
}

export async function blockUser(uid: string, ownerId: string): Promise<void> {
  const f = await need();
  await f.fsMod.updateDoc(f.fsMod.doc(f.db, "users", uid), { blockedUsers: f.fsMod.arrayUnion(ownerId) });
  rememberBlocked([...blockedLocal(), ownerId]);
}

export async function unblockUser(uid: string, ownerId: string): Promise<void> {
  const f = await need();
  await f.fsMod.updateDoc(f.fsMod.doc(f.db, "users", uid), { blockedUsers: f.fsMod.arrayRemove(ownerId) });
  rememberBlocked([...blockedLocal()].filter((x) => x !== ownerId));
}

// ---------- Şarkı tercihi / kişisel not ----------

export interface SongPreference { songId: string; selectedKeyRoot: string; capoFret: number; note: string }

export async function getPreference(uid: string, songId: string): Promise<SongPreference | null> {
  const f = await need();
  const snap = await f.fsMod.getDoc(f.fsMod.doc(f.db, "users", uid, "preferences", songId));
  if (!snap.exists()) return null;
  const x = snap.data();
  return { songId, selectedKeyRoot: String(x.selectedKeyRoot ?? ""), capoFret: Number(x.capoFret ?? 0) || 0, note: String(x.note ?? "") };
}

/**
 * Notu yazar. Döküman varsa yalnızca note alanı değişir (iOS'un kaydettiği ton ve kapo korunur);
 * yoksa iOS'un çözebileceği tam kayıt oluşur (ton/kapo: verilen varsayılanlar).
 */
export async function saveNote(uid: string, songId: string, note: string, defaults: { key: string; capo: number }): Promise<void> {
  const f = await need();
  const ref = f.fsMod.doc(f.db, "users", uid, "preferences", songId);
  const snap = await f.fsMod.getDoc(ref);
  if (snap.exists()) await f.fsMod.updateDoc(ref, { note });
  else await f.fsMod.setDoc(ref, { songId, selectedKeyRoot: defaults.key, capoFret: defaults.capo, note });
}
