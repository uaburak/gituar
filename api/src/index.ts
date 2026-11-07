// Gituar API — Cloudflare Worker + D1.
// Bütün şarkılar tek tabloda (songs). Okumalar herkese açık; yazmalar Firebase kimlik kartıyla (Authorization: Bearer).
// Silme satırı gerçekten siler. Popülerlik: kişi × şarkı × işlem başına tek kayıt (song_actions).
import { createRemoteJWKSet, jwtVerify } from "jose";
import { slugify, turkeyNormalized } from "../../shared/src/turkish.ts";
import { parse, chordSpans } from "../../shared/src/chords.ts";

interface Env {
  DB: D1Database;
  FIREBASE_PROJECT_ID: string;
  ALLOWED_ORIGINS: string;
}

type Status = "draft" | "pending" | "approved" | "rejected";
type Action = "view" | "favorite" | "repertoire";

const WEIGHTS: Record<Action, number> = { view: 1, favorite: 4, repertoire: 5 };
const LIST_FIELDS = "id, artist, artist_slug, title, slug, original_key, status, created_at, updated_at, score, owner_id";
const FULL_FIELDS = `${LIST_FIELDS}, content, added_by, rhythm`; // rhythm: migrations/0002_rhythm.sql
const MAX_LIMIT = 100;
const TRENDING_DAYS = 30;

// ---------- Yardımcılar ----------

/**
 * Dizin satırı (web sitesi ve uygulamanın bellekte tuttuğu hafif kayıt): içerik yok, yerine içerikten türeyenler var.
 *  chords: kâğıttaki akorlar (ilk görülme sırasıyla, tekrar yok, boşlukla ayrık) → akor/ton/kolay/kapo sayfaları
 *  ch:     sadeleştirilmiş içeriğin özeti → kopya şarkı tespiti (canonical)
 * İçerik yalnızca şarkı sayfası açılınca, o şarkı için ayrıca istenir.
 */
function derived(content: string): { chords: string; ch: string } {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const line of parse(content ?? "")) {
    if (!line.isChordLine) continue;
    for (const sp of chordSpans(line.text)) if (!seen.has(sp.chord)) { seen.add(sp.chord); out.push(sp.chord); }
  }
  const norm = (content ?? "").replace(/\r/g, "").replace(/[ \t]+/g, " ").replace(/\n{2,}/g, "\n").trim();
  return { chords: out.join(" "), ch: norm.length >= 40 ? fnv(norm) : "" };
}

/** FNV-1a (64 bit, iki 32 bitlik yarı): hızlı, kopya tespiti için yeterli özet. */
function fnv(text: string): string {
  let h1 = 0x811c9dc5, h2 = 0x01000193 ^ text.length;
  for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i);
    h1 = Math.imul(h1 ^ c, 0x01000193);
    h2 = Math.imul(h2 ^ c, 0x5bd1e995);
  }
  return (h1 >>> 0).toString(16).padStart(8, "0") + (h2 >>> 0).toString(16).padStart(8, "0");
}

function toIndexRow(row: Record<string, unknown>) {
  return {
    ...toSong(row),
    addedBy: (row.added_by as string | null) ?? null,
    ...derived(row.content as string),
  };
}

/** Katalog sürümü: yayındaki en son değişiklik zamanı + şarkı sayısı. Ekleme/düzenleme/onay/silme her biri bunu değiştirir. */
async function catalogVersion(env: Env): Promise<{ v: string; max: number; count: number }> {
  const r = await env.DB.prepare("SELECT MAX(updated_at) AS m, COUNT(*) AS n FROM songs WHERE status = 'approved'").first<{ m: number | null; n: number }>();
  const max = r?.m ?? 0, count = r?.n ?? 0;
  return { v: `${max}-${count}`, max, count };
}

/** Adres sürüm (v=) taşıyorsa içerik hiç değişmez: Cloudflare ve tarayıcı bir yıl saklayabilir. */
function versioned(url: URL, fallbackSeconds: number): number {
  return url.searchParams.has("v") ? 31_536_000 : fallbackSeconds;
}

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
    // Liste kayıtlarında da var: uygulama engellenen kullanıcıların şarkılarını listelerde gizler
    ownerId: (row.owner_id as string | null) ?? null,
  };
  if (!full) return base;
  return { ...base, content: row.content as string, addedBy: (row.added_by as string | null) ?? null, ...parseRhythm(row.rhythm) };
}

/** rhythm sütunu (JSON) → { rhythm, arpeggio, tempo, meter } (olmayan alanlar yazılmaz) */
function parseRhythm(raw: unknown): { rhythm?: string; arpeggio?: string; tempo?: number; meter?: string } {
  if (typeof raw !== "string" || !raw) return {};
  try {
    const r = JSON.parse(raw) as { pattern?: string; arpeggio?: string; tempo?: number; meter?: string };
    return {
      ...(r.pattern ? { rhythm: r.pattern } : {}),
      ...(r.arpeggio ? { arpeggio: r.arpeggio } : {}),
      ...(r.tempo ? { tempo: r.tempo } : {}),
      ...(r.meter ? { meter: r.meter } : {}),
    };
  } catch {
    return {};
  }
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
  /** Ritim deseni: "↓ · ↓ ↑ · ↑ ↓ ↑" ya da "A A YYAY" */
  rhythm?: string;
  /** Arpej deseni: "B 3 2 1 2 3" */
  arpeggio?: string;
  /** BPM */
  tempo?: number;
  /** "4/4", "3/4", "6/8" */
  meter?: string;
}

function cleanInput(input: SongInput, partial: boolean) {
  const artist = input.artist?.trim();
  const title = input.title?.trim();
  if (!partial || artist !== undefined) if (!artist) throw new HttpError(400, "Sanatçı gerekli");
  if (!partial || title !== undefined) if (!title) throw new HttpError(400, "Şarkı adı gerekli");
  if ((artist?.length ?? 0) > 120 || (title?.length ?? 0) > 160) throw new HttpError(400, "Ad çok uzun");
  if ((input.content?.length ?? 0) > 20000) throw new HttpError(400, "İçerik çok uzun");
  if (objectionable(artist ?? "", title ?? "", input.content ?? "")) throw new HttpError(422, "İçerik uygunsuz ifade içeriyor");
  const rhythm = input.rhythm?.trim(), arpeggio = input.arpeggio?.trim(), meter = input.meter?.trim();
  if ((rhythm?.length ?? 0) > 100 || (arpeggio?.length ?? 0) > 100) throw new HttpError(400, "Ritim deseni çok uzun");
  if (input.tempo !== undefined && !(Number(input.tempo) >= 30 && Number(input.tempo) <= 300)) throw new HttpError(400, "Tempo 30–300 arası olmalı");
  if (meter && !/^\d{1,2}\/\d{1,2}$/.test(meter)) throw new HttpError(400, "Tartım 4/4 gibi yazılmalı");
  const hasRhythm = Boolean(rhythm || arpeggio || input.tempo || meter);
  return {
    artist, title, originalKey: input.originalKey?.trim(), content: input.content?.replace(/\r/g, "").trim(),
    rhythm: hasRhythm ? { pattern: rhythm || undefined, arpeggio: arpeggio || undefined, tempo: input.tempo ? Number(input.tempo) : undefined, meter: meter || undefined } : undefined,
  };
}

/**
 * Aynı slug'a sahip sanatçı zaten varsa onun yazımı kullanılır: "yolcu kuslar" → "Yolcu Kuşlar".
 * Böylece aynı sanatçı farklı yazımlarla ikiye bölünmez (gruplama zaten slug'a göre; bu, görünen adı da birleştirir).
 */
async function canonicalArtist(env: Env, artistSlug: string, typed: string): Promise<string> {
  const row = await env.DB.prepare(
    "SELECT artist, COUNT(*) AS n FROM songs WHERE artist_slug = ? GROUP BY artist ORDER BY n DESC LIMIT 1",
  ).bind(artistSlug).first<{ artist: string }>();
  return row?.artist ?? typed;
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

  // Katalog sürümü: istemciler yalnızca bu değişince değişiklikleri ister (çok ucuz, 15 sn önbellek)
  if (method === "GET" && path === "/v1/version") {
    return json(await catalogVersion(env), {}, 15);
  }

  // Hafif dizin: içeriksiz satırlar + türetilmiş akorlar/özet, sayfalı. ?v=<sürüm> ile çağrılınca kalıcı önbelleklenir.
  if (method === "GET" && path === "/v1/index") {
    const limit = intParam(url, "limit", 2000, 5000);
    const offset = intParam(url, "offset", 0, 10_000_000);
    const { results } = await env.DB.prepare(`SELECT ${FULL_FIELDS} FROM songs WHERE status = 'approved' ORDER BY created_at, id LIMIT ? OFFSET ?`)
      .bind(limit, offset).all();
    return json({ songs: results.map(toIndexRow) }, {}, versioned(url, 60));
  }

  // Fark: since (ms) sonrasında değişen bütün satırlar (her durumda; yayından kalkanlar status ile gelir, istemci çıkarır).
  // Silinen satırlar burada görünmez: istemci şarkı sayısı tutmazsa /v1/ids ile karşılaştırır.
  if (method === "GET" && path === "/v1/changes") {
    const since = Number(url.searchParams.get("since"));
    if (!Number.isFinite(since) || since < 0) throw new HttpError(400, "since gerekli");
    const limit = intParam(url, "limit", 500, 1000);
    const { results } = await env.DB.prepare(`SELECT ${FULL_FIELDS} FROM songs WHERE updated_at > ? ORDER BY updated_at LIMIT ?`)
      .bind(since, limit + 1).all();
    const more = results.length > limit;
    // content=1: satırlar şarkı metniyle gelir (uygulamanın çevrim dışı kopyası için)
    const withContent = url.searchParams.get("content") === "1";
    const rows = results.slice(0, limit).map((r) => (withContent ? { ...toIndexRow(r), content: r.content as string, ...parseRhythm(r.rhythm) } : toIndexRow(r)));
    return json({ songs: rows, more, version: await catalogVersion(env) }, {}, versioned(url, 0));
  }

  // Yayındaki bütün şarkı numaraları (silinenleri bulmak için)
  if (method === "GET" && path === "/v1/ids") {
    const { results } = await env.DB.prepare("SELECT id FROM songs WHERE status = 'approved'").all<{ id: string }>();
    return json({ ids: results.map((r) => r.id) }, {}, versioned(url, 30));
  }

  // Popülerlik puanları (puanı olan şarkılar). Puan değişimi sürümü değiştirmez; istemci bunu ayrıca, seyrek çeker.
  if (method === "GET" && path === "/v1/scores") {
    const { results } = await env.DB.prepare("SELECT id, score FROM songs WHERE status = 'approved' AND score > 0").all<{ id: string; score: number }>();
    return json({ scores: results.map((r) => [r.id, r.score]) }, {}, 300);
  }

  // Web derlemesi: yayındaki bütün şarkılar, içerikleriyle, sayfalı
  if (method === "GET" && path === "/v1/export") {
    const limit = intParam(url, "limit", 500, 1000);
    const offset = intParam(url, "offset", 0, 10_000_000);
    const { results } = await env.DB.prepare(`SELECT ${FULL_FIELDS} FROM songs WHERE status = 'approved' ORDER BY created_at, id LIMIT ? OFFSET ?`)
      .bind(limit, offset).all();
    // ?v=<sürüm>: çevrim dışı tam indirme; aynı sürüm Cloudflare önbelleğinden gelir
    return json({ songs: results.map((r) => toSong(r, true)) }, {}, versioned(url, 0));
  }

  if (method === "GET" && (match = m(/^\/v1\/songs\/by-slug\/([^/]+)\/([^/]+)$/))) {
    const row = await env.DB.prepare(`SELECT ${FULL_FIELDS} FROM songs WHERE artist_slug = ? AND slug = ? AND status = 'approved'`)
      .bind(decodeURIComponent(match[1]), decodeURIComponent(match[2])).first<Record<string, unknown>>();
    if (!row) throw new HttpError(404, "Şarkı bulunamadı");
    // ?v=<updatedAt>: o sürümün içeriği değişmez, kalıcı önbelleklenebilir (sürüm tutmazsa kısa süre)
    const v = url.searchParams.get("v");
    return json({ song: toSong(row, true) }, {}, v && v === String(row.updated_at) ? 31_536_000 : 60);
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
      const typedArtist = c.artist ?? (row.artist as string);
      const title = c.title ?? (row.title as string);
      const artistSlug = slugify(typedArtist);
      // Başka bir sanatçıya taşınıyorsa onun yazımı kullanılır; aynı sanatçının adı düzeltiliyorsa yazılan hâli kalır
      const artist = artistSlug !== row.artist_slug ? await canonicalArtist(env, artistSlug, typedArtist) : typedArtist;
      const slug = artistSlug === row.artist_slug && title === row.title ? (row.slug as string) : await uniqueSlug(env, artistSlug, title, id);
      const status = allowedStatus(user, input.status, row.status as Status);
      await env.DB.prepare(
        `UPDATE songs SET artist = ?, artist_slug = ?, title = ?, slug = ?, original_key = ?, content = ?, status = ?, updated_at = ?, search = ?, rhythm = ? WHERE id = ?`,
      ).bind(artist, artistSlug, title, slug, c.originalKey ?? row.original_key, c.content ?? row.content, status, Date.now(),
        turkeyNormalized(`${artist} ${title}`), c.rhythm ? JSON.stringify({ ...JSON.parse((row.rhythm as string) || "{}"), ...c.rhythm }) : (row.rhythm ?? null), id).run();
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
    c.artist = await canonicalArtist(env, artistSlug, c.artist!);
    const slug = await uniqueSlug(env, artistSlug, c.title!);
    const now = Date.now();
    const id = newId();
    const status = allowedStatus(user, input.status ?? "pending");
    await env.DB.prepare(
      `INSERT INTO songs (id, artist, artist_slug, title, slug, original_key, content, status, owner_id, added_by, created_at, updated_at, search, rhythm)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    ).bind(id, c.artist, artistSlug, c.title, slug, c.originalKey ?? "", c.content ?? "", status, user.uid,
      input.addedBy?.trim() || user.name || null, now, now, turkeyNormalized(`${c.artist} ${c.title}`),
      c.rhythm ? JSON.stringify(c.rhythm) : null).run();
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

  // Hesap silme (App Store 5.1.1(v)): kullanıcının şarkıları ve popülerlik kayıtları silinir
  if (method === "DELETE" && path === "/v1/me") {
    const user = await requireUser(req, env);
    const actor = (await sha256(`gituar:u:${user.uid}`)).slice(0, 32);
    const own = await env.DB.prepare("SELECT id FROM songs WHERE owner_id = ?").bind(user.uid).all<{ id: string }>();
    const ids = own.results.map((r) => r.id);
    // Kullanıcının başka şarkılara verdiği puanlar geri alınır
    const given = await env.DB.prepare("SELECT song_id, action FROM song_actions WHERE actor = ?").bind(actor).all<{ song_id: string; action: Action }>();
    const stmts = given.results.map((g) => env.DB.prepare("UPDATE songs SET score = MAX(score - ?, 0) WHERE id = ?").bind(WEIGHTS[g.action], g.song_id));
    stmts.push(env.DB.prepare("DELETE FROM song_actions WHERE actor = ?").bind(actor));
    for (const id of ids) {
      stmts.push(env.DB.prepare("DELETE FROM song_actions WHERE song_id = ?").bind(id));
      stmts.push(env.DB.prepare("DELETE FROM songs WHERE id = ?").bind(id));
    }
    await env.DB.batch(stmts);
    return json({ deletedSongs: ids.length });
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

/**
 * GET yanıtlarına içerik özeti (ETag) eklenir. İstemci aynı özeti If-None-Match ile gönderirse gövde yerine
 * 304 döner: veri değişmediyse tekrar indirilmez (uygulama ve web aynı yolu kullanır).
 */
async function withEtag(req: Request, res: Response): Promise<Response> {
  if (req.method !== "GET" || res.status !== 200) return res;
  const text = await res.text();
  const tag = `W/"${fnv(text)}"`;
  const headers = new Headers(res.headers);
  headers.set("ETag", tag);
  const inm = req.headers.get("If-None-Match");
  if (inm && inm.split(",").map((s) => s.trim()).includes(tag)) return new Response(null, { status: 304, headers });
  return new Response(text, { status: 200, headers });
}

function cors(req: Request, env: Env, res: Response): Response {
  const origin = req.headers.get("Origin");
  if (!origin) return res;
  const allowed = env.ALLOWED_ORIGINS.split(",").map((s) => s.trim());
  // Yerel geliştirme: localhost / 127.0.0.1 her portta (tarayıcı kimlik kartını yalnızca sayfanın kendi koduna verir)
  const ok = allowed.includes(origin) || /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin) || /^https:\/\/[a-z0-9-]+-uaburaks-projects\.vercel\.app$/.test(origin);
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
      return cors(req, env, await withEtag(req, await route(req, env, url)));
    } catch (e) {
      if (e instanceof HttpError) return cors(req, env, json({ error: e.message }, { status: e.status }));
      console.error(e);
      return cors(req, env, json({ error: "Sunucu hatası" }, { status: 500 }));
    }
  },
} satisfies ExportedHandler<Env>;
