// Gituar API — Cloudflare Worker + D1.
// Bütün şarkılar tek tabloda (songs). Okumalar herkese açık; yazmalar Firebase kimlik kartıyla (Authorization: Bearer).
// Silme satırı gerçekten siler. Popülerlik: kişi × şarkı × işlem başına tek kayıt (song_actions).
import { createRemoteJWKSet, jwtVerify } from "jose";
import { slugify, turkeyNormalized } from "../../shared/src/turkish.ts";

interface Env {
  DB: D1Database;
  FIREBASE_PROJECT_ID: string;
  ALLOWED_ORIGINS: string;
}

type Status = "draft" | "pending" | "approved" | "rejected";
type Action = "view" | "favorite" | "repertoire";

const WEIGHTS: Record<Action, number> = { view: 1, favorite: 4, repertoire: 5 };
const LIST_FIELDS = "id, artist, artist_slug, title, slug, original_key, status, created_at, updated_at, score";
const FULL_FIELDS = `${LIST_FIELDS}, content, owner_id, added_by`;
const MAX_LIMIT = 100;
const TRENDING_DAYS = 30;

// ---------- Yardımcılar ----------

class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

function json(data: unknown, init: ResponseInit = {}, cacheSeconds = 0): Response {
  const headers = new Headers(init.headers);
  headers.set("Content-Type", "application/json; charset=utf-8");
  headers.set("Cache-Control", cacheSeconds > 0 ? `public, max-age=${cacheSeconds}` : "no-store");
  return new Response(JSON.stringify(data), { ...init, headers });
}

function toSong(row: Record<string, unknown>, full = false) {
  const base = {
    id: row.id as string,
    artist: row.artist as string,
    artistSlug: row.artist_slug as string,
    title: row.title as string,
    slug: row.slug as string,
    originalKey: row.original_key as string,
    status: row.status as Status,
    createdAt: row.created_at as number,
    updatedAt: row.updated_at as number,
    score: row.score as number,
  };
  if (!full) return base;
  return { ...base, content: row.content as string, ownerId: (row.owner_id as string | null) ?? null, addedBy: (row.added_by as string | null) ?? null };
}

function intParam(url: URL, name: string, def: number, max = MAX_LIMIT): number {
  const v = Number(url.searchParams.get(name));
  return Number.isFinite(v) && v > 0 ? Math.min(Math.floor(v), max) : def;
}

async function body<T>(req: Request): Promise<T> {
  try {
    return (await req.json()) as T;
  } catch {
    throw new HttpError(400, "Geçersiz JSON");
  }
}

function newId(): string {
  return crypto.randomUUID().replace(/-/g, "").slice(0, 16);
}

async function sha256(text: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// Apple Guideline 1.2: bariz küfür/hakaret içeren gönderiler sunucuda da reddedilir (iOS ContentFilter ile aynı liste).
const BLOCKED = new Set([
  "amk", "amina", "aminakoyim", "amcik", "orospu", "orospucocugu", "pic", "pezevenk", "yarrak", "yarak",
  "siktir", "sikerim", "sikeyim", "sikik", "gavat", "kahpe", "ibne", "gotveren", "kaltak", "surtuk",
  "fuck", "fucking", "motherfucker", "shit", "bitch", "cunt", "pussy", "nigger", "faggot", "whore",
]);
function objectionable(...texts: string[]): boolean {
  return texts.some((t) => turkeyNormalized(t).split(/[^a-z]+/).some((w) => BLOCKED.has(w)));
}

// ---------- Kimlik (Firebase ID token) ----------

const JWKS = createRemoteJWKSet(new URL("https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"));

interface User {
  uid: string;
  name: string;
  isAdmin: boolean;
}

async function optionalUser(req: Request, env: Env): Promise<User | null> {
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return null;
  try {
    const { payload } = await jwtVerify(auth.slice(7), JWKS, {
      issuer: `https://securetoken.google.com/${env.FIREBASE_PROJECT_ID}`,
      audience: env.FIREBASE_PROJECT_ID,
    });
    const uid = String(payload.sub ?? "");
    if (!uid) return null;
    const admin = await env.DB.prepare("SELECT 1 FROM admins WHERE uid = ?").bind(uid).first();
    return { uid, name: String(payload.name ?? payload.email ?? ""), isAdmin: Boolean(admin) };
  } catch {
    throw new HttpError(401, "Oturum geçersiz ya da süresi dolmuş");
  }
}

async function requireUser(req: Request, env: Env): Promise<User> {
  const user = await optionalUser(req, env);
  if (!user) throw new HttpError(401, "Giriş gerekli");
  return user;
}

async function requireAdmin(req: Request, env: Env): Promise<User> {
  const user = await requireUser(req, env);
  if (!user.isAdmin) throw new HttpError(403, "Yalnızca yöneticiler");
  return user;
}

// ---------- Şarkı yazma ----------

interface SongInput {
  artist?: string;
  title?: string;
  originalKey?: string;
  content?: string;
  status?: Status;
  addedBy?: string;
}

function cleanInput(input: SongInput, partial: boolean) {
  const artist = input.artist?.trim();
  const title = input.title?.trim();
  if (!partial || artist !== undefined) if (!artist) throw new HttpError(400, "Sanatçı gerekli");
  if (!partial || title !== undefined) if (!title) throw new HttpError(400, "Şarkı adı gerekli");
  if ((artist?.length ?? 0) > 120 || (title?.length ?? 0) > 160) throw new HttpError(400, "Ad çok uzun");
  if ((input.content?.length ?? 0) > 20000) throw new HttpError(400, "İçerik çok uzun");
  if (objectionable(artist ?? "", title ?? "", input.content ?? "")) throw new HttpError(422, "İçerik uygunsuz ifade içeriyor");
  return { artist, title, originalKey: input.originalKey?.trim(), content: input.content?.replace(/\r/g, "").trim() };
}

async function uniqueSlug(env: Env, artistSlug: string, title: string, exceptId?: string): Promise<string> {
  const base = slugify(title);
  for (let n = 1; n < 500; n++) {
    const slug = n === 1 ? base : `${base}-${n}`;
    const hit = await env.DB.prepare("SELECT id FROM songs WHERE artist_slug = ? AND slug = ?").bind(artistSlug, slug).first<{ id: string }>();
    if (!hit || hit.id === exceptId) return slug;
  }
  return `${base}-${newId().slice(0, 6)}`;
}

/** Sahibi olmayan kullanıcı yalnızca taslak ya da onaya gönderebilir; yönetici doğrudan yayımlar. */
function allowedStatus(user: User, requested: Status | undefined, current?: Status): Status {
  if (user.isAdmin) return requested === "draft" ? "draft" : requested ?? "approved";
  if (requested === "pending") return current === "approved" ? "approved" : "pending";
  if (requested === "draft") return current === "approved" ? "approved" : "draft";
  return current ?? "draft";
}

async function loadSong(env: Env, id: string) {
  const row = await env.DB.prepare(`SELECT ${FULL_FIELDS} FROM songs WHERE id = ?`).bind(id).first<Record<string, unknown>>();
  if (!row) throw new HttpError(404, "Şarkı bulunamadı");
  return row;
}

// ---------- Uçlar ----------

async function route(req: Request, env: Env, url: URL): Promise<Response> {
  const path = url.pathname.replace(/\/+$/, "") || "/";
  const m = (re: RegExp) => re.exec(path);
  const method = req.method;
  let match: RegExpExecArray | null;

  if (path === "/" || path === "/v1") return json({ name: "gituar-api", version: 1 });

  // Liste: yeni, popüler (tüm zamanlar), yükselen (son 30 gün)
  if (method === "GET" && path === "/v1/songs") {
    const limit = intParam(url, "limit", 20);
    const offset = intParam(url, "offset", 0, 1_000_000);
    const sort = url.searchParams.get("sort") ?? "new";
    if (sort === "trending") {
      const since = Date.now() - TRENDING_DAYS * 86_400_000;
      const { results } = await env.DB.prepare(
        `SELECT ${LIST_FIELDS.split(", ").map((f) => "s." + f).join(", ")}, t.points FROM (
           SELECT song_id, SUM(CASE action WHEN 'view' THEN 1 WHEN 'favorite' THEN 4 ELSE 5 END) AS points
           FROM song_actions WHERE created_at > ? GROUP BY song_id
         ) t JOIN songs s ON s.id = t.song_id AND s.status = 'approved'
         ORDER BY t.points DESC, s.created_at DESC LIMIT ? OFFSET ?`,
      ).bind(since, limit, offset).all();
      return json({ songs: results.map((r) => toSong(r)) }, {}, 300);
    }
    const order = sort === "popular" ? "score DESC, created_at DESC" : sort === "title" ? "title COLLATE NOCASE" : "created_at DESC";
    const { results } = await env.DB.prepare(`SELECT ${LIST_FIELDS} FROM songs WHERE status = 'approved' ORDER BY ${order} LIMIT ? OFFSET ?`)
      .bind(limit, offset).all();
    return json({ songs: results.map((r) => toSong(r)) }, {}, 60);
  }

  // Repertuarlar için: birden çok şarkı (en fazla 100 id)
  if (method === "GET" && path === "/v1/songs/batch") {
    const ids = (url.searchParams.get("ids") ?? "").split(",").map((s) => s.trim()).filter(Boolean).slice(0, MAX_LIMIT);
    if (!ids.length) return json({ songs: [] });
    const { results } = await env.DB.prepare(`SELECT ${LIST_FIELDS} FROM songs WHERE status = 'approved' AND id IN (${ids.map(() => "?").join(",")})`)
      .bind(...ids).all();
    return json({ songs: results.map((r) => toSong(r)) }, {}, 60);
  }

  // Web derlemesi: yayındaki bütün şarkılar, içerikleriyle, sayfalı
  if (method === "GET" && path === "/v1/export") {
    const limit = intParam(url, "limit", 500, 1000);
    const offset = intParam(url, "offset", 0, 10_000_000);
    const { results } = await env.DB.prepare(`SELECT ${FULL_FIELDS} FROM songs WHERE status = 'approved' ORDER BY created_at, id LIMIT ? OFFSET ?`)
      .bind(limit, offset).all();
    return json({ songs: results.map((r) => toSong(r, true)) });
  }

  if (method === "GET" && (match = m(/^\/v1\/songs\/by-slug\/([^/]+)\/([^/]+)$/))) {
    const row = await env.DB.prepare(`SELECT ${FULL_FIELDS} FROM songs WHERE artist_slug = ? AND slug = ? AND status = 'approved'`)
      .bind(decodeURIComponent(match[1]), decodeURIComponent(match[2])).first<Record<string, unknown>>();
    if (!row) throw new HttpError(404, "Şarkı bulunamadı");
    return json({ song: toSong(row, true) }, {}, 60);
  }

  if ((match = m(/^\/v1\/songs\/([^/]+)$/))) {
    const id = decodeURIComponent(match[1]);
    if (method === "GET") {
      const row = await loadSong(env, id);
      if (row.status !== "approved") {
        // Yayında olmayan şarkıyı yalnızca sahibi ve yönetici görür
        const user = await optionalUser(req, env);
        if (!user || (!user.isAdmin && user.uid !== row.owner_id)) throw new HttpError(404, "Şarkı bulunamadı");
        return json({ song: toSong(row, true) });
      }
      return json({ song: toSong(row, true) }, {}, 60);
    }
    if (method === "PATCH") {
      const user = await requireUser(req, env);
      const row = await loadSong(env, id);
      if (!user.isAdmin && user.uid !== row.owner_id) throw new HttpError(403, "Bu şarkıyı düzenleyemezsin");
      const input = await body<SongInput>(req);
      const c = cleanInput(input, true);
      const artist = c.artist ?? (row.artist as string);
      const title = c.title ?? (row.title as string);
      const artistSlug = slugify(artist);
      const slug = artistSlug === row.artist_slug && title === row.title ? (row.slug as string) : await uniqueSlug(env, artistSlug, title, id);
      const status = allowedStatus(user, input.status, row.status as Status);
      await env.DB.prepare(
        `UPDATE songs SET artist = ?, artist_slug = ?, title = ?, slug = ?, original_key = ?, content = ?, status = ?, updated_at = ?, search = ? WHERE id = ?`,
      ).bind(artist, artistSlug, title, slug, c.originalKey ?? row.original_key, c.content ?? row.content, status, Date.now(),
        turkeyNormalized(`${artist} ${title}`), id).run();
      return json({ song: toSong(await loadSong(env, id), true) });
    }
    if (method === "DELETE") {
      const user = await requireUser(req, env);
      const row = await loadSong(env, id);
      if (!user.isAdmin && user.uid !== row.owner_id) throw new HttpError(403, "Bu şarkıyı silemezsin");
      // Gerçek silme: satır ve popülerlik kayıtları gider
      await env.DB.batch([
        env.DB.prepare("DELETE FROM song_actions WHERE song_id = ?").bind(id),
        env.DB.prepare("DELETE FROM songs WHERE id = ?").bind(id),
      ]);
      return json({ deleted: id });
    }
  }

  if (method === "POST" && path === "/v1/songs") {
    const user = await requireUser(req, env);
    const input = await body<SongInput>(req);
    const c = cleanInput(input, false);
    const artistSlug = slugify(c.artist!);
    const slug = await uniqueSlug(env, artistSlug, c.title!);
    const now = Date.now();
    const id = newId();
    const status = allowedStatus(user, input.status ?? "pending");
    await env.DB.prepare(
      `INSERT INTO songs (id, artist, artist_slug, title, slug, original_key, content, status, owner_id, added_by, created_at, updated_at, search)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    ).bind(id, c.artist, artistSlug, c.title, slug, c.originalKey ?? "", c.content ?? "", status, user.uid,
      input.addedBy?.trim() || user.name || null, now, now, turkeyNormalized(`${c.artist} ${c.title}`)).run();
    return json({ song: toSong(await loadSong(env, id), true) }, { status: 201 });
  }

  // Sanatçılar: alfabetik, şarkı sayısıyla
  if (method === "GET" && path === "/v1/artists") {
    const limit = intParam(url, "limit", 5000, 10000);
    const offset = intParam(url, "offset", 0, 1_000_000);
    const { results } = await env.DB.prepare(
      `SELECT artist_slug AS slug, MIN(artist) AS name, COUNT(*) AS songs, SUM(score) AS score
       FROM songs WHERE status = 'approved' GROUP BY artist_slug ORDER BY name COLLATE NOCASE LIMIT ? OFFSET ?`,
    ).bind(limit, offset).all();
    return json({ artists: results }, {}, 300);
  }

  if (method === "GET" && (match = m(/^\/v1\/artists\/([^/]+)$/))) {
    const slug = decodeURIComponent(match[1]);
    const { results } = await env.DB.prepare(`SELECT ${LIST_FIELDS} FROM songs WHERE status = 'approved' AND artist_slug = ? ORDER BY title COLLATE NOCASE`)
      .bind(slug).all();
    if (!results.length) throw new HttpError(404, "Sanatçı bulunamadı");
    return json({ artist: { slug, name: results[0].artist, songs: results.map((r) => toSong(r)) } }, {}, 120);
  }

  // Arama: 3+ harfte üçlü harf dizini, daha kısada önek araması
  if (method === "GET" && path === "/v1/search") {
    const q = turkeyNormalized((url.searchParams.get("q") ?? "").trim()).replace(/["*]/g, " ").replace(/\s+/g, " ").trim();
    const limit = intParam(url, "limit", 30);
    if (!q) return json({ songs: [], artists: [] });
    let rows: Record<string, unknown>[];
    const terms = q.split(" ").filter((t) => t.length >= 3).map((t) => `"${t}"`).join(" AND ");
    if (terms) {
      const res = await env.DB.prepare(
        `SELECT ${LIST_FIELDS.split(", ").map((f) => "s." + f).join(", ")} FROM songs_fts f JOIN songs s ON s.rowid = f.rowid
         WHERE songs_fts MATCH ? AND s.status = 'approved' ORDER BY s.score DESC, s.title LIMIT ?`,
      ).bind(terms, limit).all();
      rows = res.results;
    } else {
      const res = await env.DB.prepare(`SELECT ${LIST_FIELDS} FROM songs WHERE status = 'approved' AND search LIKE ? ORDER BY score DESC LIMIT ?`)
        .bind(`%${q}%`, limit).all();
      rows = res.results;
    }
    const artists = new Map<string, { slug: string; name: string; songs: number }>();
    for (const r of rows) {
      if (!turkeyNormalized(String(r.artist)).includes(q.split(" ")[0])) continue;
      const a = artists.get(String(r.artist_slug)) ?? { slug: String(r.artist_slug), name: String(r.artist), songs: 0 };
      a.songs++;
      artists.set(a.slug, a);
    }
    return json({ songs: rows.map((r) => toSong(r)), artists: [...artists.values()].slice(0, 5) }, {}, 60);
  }

  // Popülerlik: kişi × şarkı × işlem tek kayıt. view geri alınmaz; favorite/repertoire active:false ile geri alınır.
  if (method === "POST" && path === "/v1/actions") {
    const input = await body<{ songId?: string; action?: Action; active?: boolean; deviceId?: string }>(req);
    const action = input.action;
    if (!input.songId || !action || !(action in WEIGHTS)) throw new HttpError(400, "songId ve action gerekli");
    const user = await optionalUser(req, env).catch(() => null);
    const raw = user ? `u:${user.uid}` : input.deviceId && /^[a-zA-Z0-9-]{16,64}$/.test(input.deviceId) ? `d:${input.deviceId}` : "";
    if (!raw) throw new HttpError(400, "Kimlik yok");
    if (action !== "view" && !user) throw new HttpError(401, "Giriş gerekli");
    const actor = (await sha256(`gituar:${raw}`)).slice(0, 32);
    const exists = await env.DB.prepare("SELECT 1 FROM songs WHERE id = ? AND status = 'approved'").bind(input.songId).first();
    if (!exists) return json({ counted: false });
    const w = WEIGHTS[action];
    if (input.active === false && action !== "view") {
      const res = await env.DB.prepare("DELETE FROM song_actions WHERE song_id = ? AND actor = ? AND action = ?").bind(input.songId, actor, action).run();
      if (res.meta.changes > 0) await env.DB.prepare("UPDATE songs SET score = MAX(score - ?, 0) WHERE id = ?").bind(w, input.songId).run();
      return json({ counted: res.meta.changes > 0 });
    }
    const res = await env.DB.prepare("INSERT OR IGNORE INTO song_actions (song_id, actor, action, created_at) VALUES (?, ?, ?, ?)")
      .bind(input.songId, actor, action, Date.now()).run();
    if (res.meta.changes > 0) await env.DB.prepare("UPDATE songs SET score = score + ? WHERE id = ?").bind(w, input.songId).run();
    return json({ counted: res.meta.changes > 0 });
  }

  if (method === "GET" && path === "/v1/me") {
    const user = await requireUser(req, env);
    return json({ uid: user.uid, isAdmin: user.isAdmin });
  }

  if (method === "GET" && path === "/v1/me/songs") {
    const user = await requireUser(req, env);
    const { results } = await env.DB.prepare(`SELECT ${FULL_FIELDS} FROM songs WHERE owner_id = ? ORDER BY updated_at DESC`).bind(user.uid).all();
    return json({ songs: results.map((r) => toSong(r, true)) });
  }

  if (method === "GET" && path === "/v1/admin/pending") {
    await requireAdmin(req, env);
    const { results } = await env.DB.prepare(`SELECT ${FULL_FIELDS} FROM songs WHERE status = 'pending' ORDER BY created_at`).all();
    return json({ songs: results.map((r) => toSong(r, true)) });
  }

  if (method === "POST" && (match = m(/^\/v1\/admin\/songs\/([^/]+)\/status$/))) {
    await requireAdmin(req, env);
    const { status } = await body<{ status?: Status }>(req);
    if (status !== "approved" && status !== "rejected") throw new HttpError(400, "status approved ya da rejected olmalı");
    const id = decodeURIComponent(match[1]);
    await loadSong(env, id);
    await env.DB.prepare("UPDATE songs SET status = ?, updated_at = ? WHERE id = ?").bind(status, Date.now(), id).run();
    return json({ song: toSong(await loadSong(env, id), true) });
  }

  throw new HttpError(404, "Bulunamadı");
}

function cors(req: Request, env: Env, res: Response): Response {
  const origin = req.headers.get("Origin");
  if (!origin) return res;
  const allowed = env.ALLOWED_ORIGINS.split(",").map((s) => s.trim());
  const ok = allowed.includes(origin) || /^https:\/\/[a-z0-9-]+-uaburaks-projects\.vercel\.app$/.test(origin);
  if (!ok) return res;
  const headers = new Headers(res.headers);
  headers.set("Access-Control-Allow-Origin", origin);
  headers.set("Access-Control-Allow-Methods", "GET, POST, PATCH, DELETE, OPTIONS");
  headers.set("Access-Control-Allow-Headers", "Authorization, Content-Type");
  headers.set("Access-Control-Max-Age", "86400");
  headers.append("Vary", "Origin");
  return new Response(res.body, { status: res.status, headers });
}

export default {
  async fetch(req, env): Promise<Response> {
    const url = new URL(req.url);
    if (req.method === "OPTIONS") return cors(req, env, new Response(null, { status: 204 }));
    try {
      return cors(req, env, await route(req, env, url));
    } catch (e) {
      if (e instanceof HttpError) return cors(req, env, json({ error: e.message }, { status: e.status }));
      console.error(e);
      return cors(req, env, json({ error: "Sunucu hatası" }, { status: 500 }));
    }
  },
} satisfies ExportedHandler<Env>;
