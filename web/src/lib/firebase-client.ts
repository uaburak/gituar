// Tarayıcı tarafı Firebase erişimi. SDK yalnızca gerektiğinde (giriş, repertuar, Pro) yüklenir.
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

type ProField = { active?: boolean; until?: { toDate(): Date } | null } | undefined;
/** Alan geçerli mi: active ve süresi dolmamış (until yoksa süresiz). */
function proValid(p: ProField): boolean {
  const until = p?.until?.toDate?.();
  return p?.active === true && (!until || until > new Date());
}

/**
 * Pro durumu: App Store aboneliği (`users/{uid}.pro`, uygulama yazar) ya da hediye Pro
 * (`users/{uid}.proGrant`, yalnızca yönetici yazar). Sonuç localStorage'a ve <html class="pro"> olarak yazılır.
 */
export async function refreshPro(uid: string): Promise<boolean> {
  const f = await fb();
  if (!f) return false;
  let active = false;
  try {
    const data = (await f.fsMod.getDoc(f.fsMod.doc(f.db, "users", uid))).data();
    active = proValid(data?.pro as ProField) || proValid(data?.proGrant as ProField);
  } catch {
    active = localStorage.getItem("gituar-pro") === "1";
  }
  setPro(active);
  return active;
}

export function setPro(active: boolean): void {
  try {
    localStorage.setItem("gituar-pro", active ? "1" : "0");
  } catch {}
  document.documentElement.classList.toggle("pro", active);
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

/**
 * Herkese açık bir repertuarı kullanıcının kendi (gizli) repertuarlarına kopyalar — iOS'taki "Repertuarlarıma kaydet"
 * ile aynı: kopya `sourceId` ile kaynağına bağlanır, isPublic: false.
 */
export async function copyRepertoire(uid: string, source: { id: string; name: string; songIds: string[] }): Promise<string> {
  const f = await fb();
  if (!f) throw new Error("Firebase hazır değil");
  const ref = f.fsMod.doc(f.fsMod.collection(f.db, "users", uid, "repertoires"));
  await f.fsMod.setDoc(ref, {
    name: source.name, songIds: source.songIds, ownerId: uid, createdAt: f.fsMod.Timestamp.now(), isPublic: false, sourceId: source.id,
  });
  return ref.id;
}

/** Bu herkese açık repertuar kullanıcının listelerine daha önce kaydedildi mi? (kopyanın sourceId'si) */
export async function isRepertoireCopied(uid: string, sourceId: string): Promise<boolean> {
  const f = await fb();
  if (!f) return false;
  const snap = await f.fsMod.getDocs(f.fsMod.query(f.fsMod.collection(f.db, "users", uid, "repertoires"), f.fsMod.where("sourceId", "==", sourceId)));
  return !snap.empty;
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
    // Aynı okumada engel listesi de tazelenir (listeler ve şarkı sayfası bu tarayıcı kopyasını kullanır)
    const blocked = snap.data()?.blockedUsers;
    try { localStorage.setItem("gituar-blocked", JSON.stringify(Array.isArray(blocked) ? blocked : [])); } catch {}
  } catch {
    admin = false;
  }
  try { localStorage.setItem("gituar-admin", admin ? "1" : "0"); } catch {}
  return admin;
}

const toDate = (v: unknown): Date | undefined => (v as { toDate?: () => Date } | undefined)?.toDate?.();

// ---------- Pro yönetimi (yalnızca yönetici; kurallar proGrant'i başkasına yazdırmaz) ----------

export interface ProUser {
  uid: string;
  username: string;
  email?: string;
  /** Hediye Pro */
  gift?: { active: boolean; until?: Date; note?: string; at?: Date };
  /** App Store aboneliği (uygulamanın yazdığı) */
  subscription?: { active: boolean; until?: Date };
  isPro: boolean;
}

function toProUser(id: string, x: Record<string, unknown>): ProUser {
  const g = x.proGrant as { active?: boolean; until?: unknown; note?: string; at?: unknown } | undefined;
  const p = x.pro as { active?: boolean; until?: unknown } | undefined;
  const gift = g ? { active: g.active === true, until: toDate(g.until), note: g.note, at: toDate(g.at) } : undefined;
  const subscription = p ? { active: p.active === true, until: toDate(p.until) } : undefined;
  const valid = (v?: { active: boolean; until?: Date }) => Boolean(v?.active && (!v.until || v.until > new Date()));
  return { uid: id, username: String(x.username ?? ""), email: x.email as string | undefined, gift, subscription, isPro: valid(gift) || valid(subscription) };
}

/** Kullanıcı adıyla kullanıcıyı bulur (küçük harf, @ olmadan). */
export async function findUserByUsername(username: string): Promise<ProUser | null> {
  const f = await fb();
  if (!f) return null;
  const name = username.trim().replace(/^@/, "").toLocaleLowerCase("tr-TR");
  if (!name) return null;
  const snap = await f.fsMod.getDocs(f.fsMod.query(f.fsMod.collection(f.db, "users"), f.fsMod.where("username", "==", name), f.fsMod.limit(1)));
  const d = snap.docs[0];
  return d ? toProUser(d.id, d.data()) : null;
}

/** Hediye Pro verir; `until` yoksa süresiz. */
export async function grantPro(adminUid: string, uid: string, until: Date | null, note = ""): Promise<void> {
  const f = await fb();
  if (!f) throw new Error("Firebase hazır değil");
  await f.fsMod.updateDoc(f.fsMod.doc(f.db, "users", uid), {
    proGrant: { active: true, until: until ? f.fsMod.Timestamp.fromDate(until) : null, note, by: adminUid, at: f.fsMod.Timestamp.now() },
  });
}

/** Hediye Pro'yu geri alır (App Store aboneliğine dokunmaz). */
export async function revokePro(uid: string): Promise<void> {
  const f = await fb();
  if (!f) throw new Error("Firebase hazır değil");
  await f.fsMod.updateDoc(f.fsMod.doc(f.db, "users", uid), { proGrant: f.fsMod.deleteField() });
}

/** Hediye Pro'su ya da App Store aboneliği olan kullanıcılar. */
export async function listProUsers(): Promise<ProUser[]> {
  const f = await fb();
  if (!f) return [];
  const [gifts, subs] = await Promise.all([
    f.fsMod.getDocs(f.fsMod.query(f.fsMod.collection(f.db, "users"), f.fsMod.where("proGrant.active", "==", true))),
    f.fsMod.getDocs(f.fsMod.query(f.fsMod.collection(f.db, "users"), f.fsMod.where("pro.active", "==", true))),
  ]);
  const map = new Map<string, ProUser>();
  for (const d of [...gifts.docs, ...subs.docs]) map.set(d.id, toProUser(d.id, d.data()));
  return [...map.values()].sort((a, b) => a.username.localeCompare(b.username, "tr"));
}

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
/** Apple ile giriş (Firebase apple.com sağlayıcısı; Firebase Console'da Apple sağlayıcısı ve Services ID tanımlı olmalı). */
export async function signInApple(): Promise<void> {
  const f = await fb();
  if (!f) return;
  const provider = new f.authMod.OAuthProvider("apple.com");
  provider.addScope("email");
  provider.addScope("name");
  provider.setCustomParameters({ locale: "tr_TR" });
  await f.authMod.signInWithPopup(f.auth, provider);
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
  try { for (const k of ["gituar-auth", "gituar-user", "gituar-blocked", "gituar-admin"]) localStorage.removeItem(k); } catch {}
  setPro(false);
}

// ---------- Hesap silme (App Store 5.1.1(v) ile aynı kapsam) ----------

export class ReauthRequired extends Error {
  constructor(public method: "password" | "google" | "apple") { super("reauth"); }
}

/** Oturum 5 dakikadan eskiyse Firebase silmeyi reddeder; veriler silinmeden önce kontrol edilir. */
export async function needsReauth(user: User): Promise<"password" | "google" | "apple" | null> {
  const last = Date.parse(user.metadata.lastSignInTime ?? "");
  if (Number.isFinite(last) && Date.now() - last < 4.5 * 60 * 1000) return null;
  if (user.providerData.some((p) => p.providerId === "password")) return "password";
  return user.providerData.some((p) => p.providerId === "apple.com") ? "apple" : "google";
}

export async function reauthenticate(user: User, password?: string): Promise<void> {
  const f = await fb();
  if (!f) throw new Error("Firebase hazır değil");
  if (password !== undefined) {
    const cred = f.authMod.EmailAuthProvider.credential(user.email ?? "", password);
    await f.authMod.reauthenticateWithCredential(user, cred);
  } else {
    const apple = user.providerData.some((p) => p.providerId === "apple.com") && !user.providerData.some((p) => p.providerId === "google.com");
    await f.authMod.reauthenticateWithPopup(user, apple ? new f.authMod.OAuthProvider("apple.com") : new f.authMod.GoogleAuthProvider());
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
    for (const k of ["gituar-auth", "gituar-user", "gituar-pro", "gituar-admin"]) localStorage.removeItem(k);
  } catch {}
}

/**
 * Yönetici toplu repertuar yüklemesi (iOS bulkImportRepertoires ile aynı): her kayıt public-repertoires'a
 * herkese açık olarak, adres alanlarıyla (ownerUsername, slug) yazılır. Sıra korunsun diye createdAt birer saniye geriye gider.
 */
export async function createPublicRepertoires(uid: string, ownerUsername: string, entries: { name: string; songIds: string[] }[], onProgress?: (done: number) => void): Promise<number> {
  const f = await fb();
  if (!f) throw new Error("Firebase hazır değil");
  const fs = f.fsMod;
  const existing = await fs.getDocs(fs.query(fs.collection(f.db, "public-repertoires"), fs.where("ownerId", "==", uid)));
  const taken = new Set(existing.docs.map((d) => d.data().slug).filter((x): x is string => typeof x === "string"));
  let ok = 0;
  for (const [i, e] of entries.entries()) {
    const ref = fs.doc(fs.collection(f.db, "public-repertoires"));
    await fs.setDoc(ref, {
      name: e.name, songIds: e.songIds, ownerId: uid, isPublic: true, createdAt: fs.Timestamp.fromMillis(Date.now() - i * 1000),
      ownerUsername, slug: uniqueSlug(e.name, taken),
    });
    ok++;
    onProgress?.(ok);
  }
  return ok;
}
