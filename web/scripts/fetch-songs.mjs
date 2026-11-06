// Derlemeden önce: yayındaki bütün şarkıları Gituar API'sinden (Cloudflare D1) çeker ve .cache/songs.json'a yazar.
// Bu dosya yalnızca derleme içindir (gitignore), tarayıcıya gönderilmez. API'ye ulaşılamazsa derleme durur:
// boş ya da yarım bir site yayına çıkmasın diye.
import { mkdirSync, writeFileSync, readFileSync, existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
function env(name) {
  if (process.env[name]) return process.env[name];
  const file = resolve(root, ".env");
  if (!existsSync(file)) return "";
  const m = new RegExp(`^${name}=(.*)$`, "m").exec(readFileSync(file, "utf8"));
  return m ? m[1].trim() : "";
}
const api = (env("PUBLIC_API_URL") || "https://gituar-api.burak-kc-sp.workers.dev").replace(/\/$/, "");
const out = resolve(root, ".cache/songs.json");

const songs = [];
for (let offset = 0; ; offset += 1000) {
  const res = await fetch(`${api}/v1/export?limit=1000&offset=${offset}`);
  if (!res.ok) {
    console.error(`[songs] API hatası ${res.status}: ${(await res.text()).slice(0, 200)}`);
    process.exit(1);
  }
  const page = (await res.json()).songs;
  for (const s of page) {
    songs.push({
      id: s.id,
      artist: s.artist,
      songName: s.title,
      originalKey: s.originalKey,
      content: s.content,
      artistSlug: s.artistSlug,
      slug: s.slug,
      // seq: sıralama için oluşturulma zamanı (ms)
      seq: s.createdAt,
      createdAt: new Date(s.createdAt).toISOString(),
      updatedAt: new Date(s.updatedAt).toISOString(),
      score: s.score,
      ...(s.addedBy ? { addedBy: s.addedBy } : {}),
    });
  }
  if (page.length < 1000) break;
}
mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, JSON.stringify(songs));
console.log(`[songs] ${songs.length} şarkı API'den alındı → .cache/songs.json`);
