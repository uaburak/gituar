// Tarayıcı tarafı Firebase erişimi. SDK yalnızca gerektiğinde (giriş, repertuar, Plus) yüklenir.
import { FIREBASE_CONFIG } from "./site.ts";
import { uniqueSlug } from "./repertoire-path.ts";
import type { User } from "firebase/auth";

export const firebaseReady = Boolean(FIREBASE_CONFIG.apiKey && FIREBASE_CONFIG.appId);

type Fb = {
  auth: import("firebase/auth").Auth;
  db: import("firebase/firestore").Firestore;
  authMod: typeof import("firebase/auth");
  fsMod: typeof import("firebase/firestore");
};

let instance: Promise<Fb> | null = null;

export function fb(): Promise<Fb> | null {
  if (!firebaseReady) return null;
  if (!instance) {
    instance = (async () => {
      const [{ initializeApp, getApps }, authMod, fsMod] = await Promise.all([
        import("firebase/app"),
        import("firebase/auth"),
        import("firebase/firestore"),
      ]);
      const app = getApps()[0] ?? initializeApp(FIREBASE_CONFIG);
      return { auth: authMod.getAuth(app), db: fsMod.getFirestore(app), authMod, fsMod };
    })();
  }
  return instance;
}

export async function currentUser(): Promise<User | null> {
  const f = await fb();
  if (!f) return null;
  return new Promise((resolve) => {
    const unsub = f.authMod.onAuthStateChanged(f.auth, (u) => {
      unsub();
      resolve(u);
    });
  });
}

export function onUser(cb: (u: User | null) => void): void {
  const p = fb();
  if (!p) {
    cb(null);
    return;
  }
  p.then((f) =>
    f.authMod.onAuthStateChanged(f.auth, (u) => {
      try {
        if (u) localStorage.setItem("gituar-auth", "1");
        else { localStorage.removeItem("gituar-auth"); localStorage.removeItem("gituar-user"); }
      } catch {}
      cb(u);
    }),
  );
}

/** users/{uid}.plus alanından Plus durumunu okur; sonucu localStorage'a ve <html class="plus"> olarak yazar. */
export async function refreshPlus(uid: string): Promise<boolean> {
  const f = await fb();
  if (!f) return false;
  let active = false;
  try {
    const snap = await f.fsMod.getDoc(f.fsMod.doc(f.db, "users", uid));
    const plus = snap.data()?.plus as { active?: boolean; until?: { toDate(): Date } } | undefined;
    const until = plus?.until?.toDate?.();
    active = plus?.active === true && (!until || until > new Date());
  } catch {
    active = localStorage.getItem("gituar-plus") === "1";
  }
  setPlus(active);
  return active;
}

export function setPlus(active: boolean): void {
  try {
    localStorage.setItem("gituar-plus", active ? "1" : "0");
  } catch {}
  document.documentElement.classList.toggle("plus", active);
}

export interface RepertoireDoc {
  id: string;
  name: string;
  songIds: string[];
  ownerId: string;
  isPublic: boolean;
  createdAt?: Date;
  sourceId?: string;
  /** Herkese açık repertuarlarda adres parçaları: /repertuar/{ownerUsername}/{slug}/ */
  ownerUsername?: string;
  slug?: string;
}

// iOS ile aynı veri modeli: özel repertuarlar users/{uid}/repertoires, herkese açık olanlar public-repertoires.
function toRep(id: string, data: Record<string, unknown>, isPublic: boolean): RepertoireDoc {
  const created = data.createdAt as { toDate?: () => Date } | undefined;
  return {
    id,
    name: String(data.name ?? ""),
    songIds: Array.isArray(data.songIds) ? (data.songIds as string[]) : [],
    ownerId: String(data.ownerId ?? ""),
    isPublic: typeof data.isPublic === "boolean" ? data.isPublic : isPublic,
    createdAt: created?.toDate?.(),
    sourceId: typeof data.sourceId === "string" ? data.sourceId : undefined,
    ownerUsername: typeof data.ownerUsername === "string" ? data.ownerUsername : undefined,
    slug: typeof data.slug === "string" ? data.slug : undefined,
  };
}

/** Kullanıcının özel ve herkese açık repertuarları, en yeni önce. */
export async function listMyRepertoires(uid: string): Promise<RepertoireDoc[]> {
  const f = await fb();
  if (!f) return [];
  const [priv, pub] = await Promise.all([
    f.fsMod.getDocs(f.fsMod.collection(f.db, "users", uid, "repertoires")),
    f.fsMod.getDocs(f.fsMod.query(f.fsMod.collection(f.db, "public-repertoires"), f.fsMod.where("ownerId", "==", uid))),
  ]);
  const pubReps = pub.docs.map((d) => toRep(d.id, d.data(), true));
  await ensurePublicSlugs(f, uid, pubReps).catch(() => {});
  const all = [...priv.docs.map((d) => toRep(d.id, d.data(), false)), ...pubReps];
  return all.sort((a, b) => (b.createdAt?.getTime() ?? 0) - (a.createdAt?.getTime() ?? 0));
}

/**
 * Herkese açık repertuarlarına adres alanları (ownerUsername, slug) yoksa ekler. Eski kayıtlar ve
 * uygulamanın eski sürümleri bu alanları yazmadığı için sahibi siteye girince tamamlanır.
 * Verilen dizideki kayıtlar da yerinde güncellenir.
 */
async function ensurePublicSlugs(f: Fb, uid: string, reps: RepertoireDoc[]): Promise<void> {
  const missing = reps.filter((r) => !r.slug || !r.ownerUsername);
  if (!missing.length) return;
  const profile = await f.fsMod.getDoc(f.fsMod.doc(f.db, "users", uid));
  const username = String(profile.data()?.username ?? "").trim().toLocaleLowerCase("tr-TR");
  if (!username) return;
  const taken = new Set(reps.filter((r) => r.slug).map((r) => r.slug!));
  // Eskiden yenige: ilk yayınlanan "sahne", sonraki "sahne-2" olur
  const ordered = [...missing].sort((a, b) => (a.createdAt?.getTime() ?? 0) - (b.createdAt?.getTime() ?? 0));
  for (const r of ordered) {
    const slug = r.slug ?? uniqueSlug(r.name, taken);
    await f.fsMod.updateDoc(f.fsMod.doc(f.db, "public-repertoires", r.id), { ownerUsername: username, slug });
    r.slug = slug;
    r.ownerUsername = username;
  }
}

export async function createRepertoire(uid: string, name: string): Promise<string> {
  const f = await fb();
  if (!f) throw new Error("Firebase hazır değil");
  const ref = f.fsMod.doc(f.fsMod.collection(f.db, "users", uid, "repertoires"));
  // createdAt iOS tarafında zorunlu (Date) — Timestamp olarak yazılır
  await f.fsMod.setDoc(ref, { name, songIds: [], ownerId: uid, createdAt: f.fsMod.Timestamp.now(), isPublic: false });
  return ref.id;
}

function repRef(f: Fb, uid: string, rep: Pick<RepertoireDoc, "id" | "isPublic">) {
  return rep.isPublic ? f.fsMod.doc(f.db, "public-repertoires", rep.id) : f.fsMod.doc(f.db, "users", uid, "repertoires", rep.id);
}

export async function addSongToRepertoire(uid: string, rep: Pick<RepertoireDoc, "id" | "isPublic">, songId: string): Promise<void> {
  const f = await fb();
  if (!f) throw new Error("Firebase hazır değil");
  await f.fsMod.updateDoc(repRef(f, uid, rep), { songIds: f.fsMod.arrayUnion(songId) });
}

/** Önce herkese açık, sonra (giriş yapılmışsa) kullanıcının özel repertuarına bakar. */
export async function getRepertoire(id: string, uid?: string | null): Promise<RepertoireDoc | null> {
  const f = await fb();
  if (!f) return null;
  const pub = await f.fsMod.getDoc(f.fsMod.doc(f.db, "public-repertoires", id));
  if (pub.exists()) return toRep(pub.id, pub.data(), true);
  if (uid) {
    const priv = await f.fsMod.getDoc(f.fsMod.doc(f.db, "users", uid, "repertoires", id));
    if (priv.exists()) return toRep(priv.id, priv.data(), false);
  }
  return null;
}

// ---------- Yönetim (users/{uid}.isAdmin; kurallar sunucu tarafında da zorlar) ----------

export async function isAdminUser(uid: string): Promise<boolean> {
  const f = await fb();
  if (!f) return false;
  let admin = false;
  try {
    const snap = await f.fsMod.getDoc(f.fsMod.doc(f.db, "users", uid));
    admin = snap.data()?.isAdmin === true;
  } catch {
    admin = false;
  }
  try { localStorage.setItem("gituar-admin", admin ? "1" : "0"); } catch {}
  return admin;
}

const toDate = (v: unknown): Date | undefined => (v as { toDate?: () => Date } | undefined)?.toDate?.();

export interface ReportDoc {
  id: string;
  songId: string;
  songName: string;
  songArtist?: string;
  reason: string;
  ownerUsername?: string;
  ownerId?: string;
  reportedBy?: string;
  reportedAt?: Date;
  status: string;
}

/** Şikayetler; iOS ile aynı durumlar: pending, in_progress, reviewed, dismissed. */
export async function listReports(statuses: string[]): Promise<ReportDoc[]> {
  const f = await fb();
  if (!f) return [];
  const snap = await f.fsMod.getDocs(f.fsMod.query(f.fsMod.collection(f.db, "reports"), f.fsMod.where("status", "in", statuses)));
  return snap.docs
    .map((d) => {
      const x = d.data();
      return {
        id: d.id, songId: String(x.songId ?? ""), songName: String(x.songName ?? ""), songArtist: x.songArtist as string | undefined,
        reason: String(x.reason ?? ""), ownerUsername: x.ownerUsername as string | undefined, ownerId: x.ownerId as string | undefined,
        reportedBy: x.reportedBy as string | undefined, reportedAt: toDate(x.reportedAt), status: String(x.status ?? "pending"),
      };
    })
    .sort((a, b) => (b.reportedAt?.getTime() ?? 0) - (a.reportedAt?.getTime() ?? 0));
}

export async function setReportStatus(id: string, status: "in_progress" | "reviewed" | "dismissed"): Promise<void> {
  const f = await fb();
  if (!f) throw new Error("Firebase hazır değil");
  await f.fsMod.updateDoc(f.fsMod.doc(f.db, "reports", id), { status });
}

/** Şarkı şikayeti: iOS SongDetailView.reportContent ile aynı alanlar; admin panelinde listelenir. */
export async function createReport(uid: string, song: { id: string; name: string; artist: string }, reason: string): Promise<void> {
  const f = await fb();
  if (!f) throw new Error("firebase-not-configured");
  await f.fsMod.addDoc(f.fsMod.collection(f.db, "reports"), {
    songId: song.id,
    songName: song.name,
    songArtist: song.artist,
    reason,
    reportedAt: f.fsMod.serverTimestamp(),
    status: "pending",
    reportedBy: uid,
    source: "web",
  });
}

export async function signInGoogle(): Promise<void> {
  const f = await fb();
  if (!f) return;
  await f.authMod.signInWithPopup(f.auth, new f.authMod.GoogleAuthProvider());
}
export async function signInEmail(email: string, password: string): Promise<void> {
  const f = await fb();
  if (!f) return;
  await f.authMod.signInWithEmailAndPassword(f.auth, email, password);
}
export async function signUpEmail(email: string, password: string): Promise<void> {
  const f = await fb();
  if (!f) return;
  await f.authMod.createUserWithEmailAndPassword(f.auth, email, password);
}
export async function signOutUser(): Promise<void> {
  const f = await fb();
  if (!f) return;
  await f.authMod.signOut(f.auth);
  try { localStorage.removeItem("gituar-auth"); localStorage.removeItem("gituar-user"); } catch {}
  setPlus(false);
}

// ---------- Hesap silme (App Store 5.1.1(v) ile aynı kapsam) ----------

export class ReauthRequired extends Error {
  constructor(public method: "password" | "google") { super("reauth"); }
}

/** Oturum 5 dakikadan eskiyse Firebase silmeyi reddeder; veriler silinmeden önce kontrol edilir. */
export async function needsReauth(user: User): Promise<"password" | "google" | null> {
  const last = Date.parse(user.metadata.lastSignInTime ?? "");
  if (Number.isFinite(last) && Date.now() - last < 4.5 * 60 * 1000) return null;
  return user.providerData.some((p) => p.providerId === "password") ? "password" : "google";
}

export async function reauthenticate(user: User, password?: string): Promise<void> {
  const f = await fb();
  if (!f) throw new Error("Firebase hazır değil");
  if (password !== undefined) {
    const cred = f.authMod.EmailAuthProvider.credential(user.email ?? "", password);
    await f.authMod.reauthenticateWithCredential(user, cred);
  } else {
    await f.authMod.reauthenticateWithPopup(user, new f.authMod.GoogleAuthProvider());
  }
}

/**
 * Hesabı ve verilerini siler: şarkılar + popülerlik puanları (Cloudflare API), repertuarlar, tercihler, favoriler,
 * herkese açık repertuarlar ve profil (Firestore), son olarak giriş hesabı (Firebase Auth).
 */
export async function deleteAccount(user: User, apiUrl: string): Promise<void> {
  const f = await fb();
  if (!f) throw new Error("Firebase hazır değil");
  const method = await needsReauth(user);
  if (method) throw new ReauthRequired(method);
  const fs = f.fsMod;
  const token = await user.getIdToken();
  const res = await fetch(`${apiUrl}/v1/me`, { method: "DELETE", headers: { Authorization: `Bearer ${token}` } });
  if (!res.ok && res.status !== 404) throw new Error("Şarkıların silinemedi, lütfen tekrar dene.");
  for (const sub of ["repertoires", "preferences", "favorites"]) {
    const snap = await fs.getDocs(fs.collection(f.db, "users", user.uid, sub)).catch(() => null);
    if (snap) for (const d of snap.docs) await fs.deleteDoc(d.ref).catch(() => {});
  }
  const pub = await fs.getDocs(fs.query(fs.collection(f.db, "public-repertoires"), fs.where("ownerId", "==", user.uid))).catch(() => null);
  if (pub) for (const d of pub.docs) await fs.deleteDoc(d.ref).catch(() => {});
  await fs.deleteDoc(fs.doc(f.db, "users", user.uid)).catch(() => {});
  await f.authMod.deleteUser(user);
  try {
    for (const k of ["gituar-auth", "gituar-user", "gituar-plus", "gituar-admin"]) localStorage.removeItem(k);
  } catch {}
}
