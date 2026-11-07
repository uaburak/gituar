// Rastgele bölümü: açılınca kataloğun rastgele yerlerinden 20 şarkı getirir (iki sütun), "Başka şarkılar getir" yeniler.
// API'de rastgele sıralama yok; alfabetik listeden rastgele iki yerden 100'er şarkı alınıp içlerinden 20'si seçilir.
import { API_URL } from "../lib/site.ts";
import { toEntry, rowHtml, type SongEntry } from "../lib/search-client.ts";

const section = document.getElementById("random") as HTMLDetailsElement | null;
const list = document.getElementById("random-list");
const status = document.getElementById("random-status");
const refresh = document.getElementById("random-refresh");
const COUNT = 20;
const CHUNK = 100;

async function chunk(offset: number): Promise<SongEntry[]> {
  const res = await fetch(`${API_URL}/v1/songs?sort=title&limit=${CHUNK}&offset=${offset}`);
  if (!res.ok) throw new Error(`API ${res.status}`);
  return ((await res.json()) as { songs: Parameters<typeof toEntry>[0][] }).songs.map(toEntry);
}

function shuffle<T>(a: T[]): T[] {
  for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; }
  return a;
}

let loading = false;
async function load() {
  if (!list || loading) return;
  loading = true;
  if (status) { status.hidden = false; status.textContent = "Yükleniyor…"; }
  try {
    const total = Number(list.dataset.total) || CHUNK;
    const max = Math.max(0, total - CHUNK);
    const offsets = total <= CHUNK ? [0] : [Math.floor(Math.random() * max), Math.floor(Math.random() * max)];
    const pool = (await Promise.all(offsets.map(chunk))).flat();
    const seen = new Set<string>();
    const picks = shuffle(pool.filter((e) => !seen.has(e.i) && seen.add(e.i))).slice(0, COUNT);
    list.innerHTML = picks.map(rowHtml).join("");
    if (status) status.hidden = picks.length > 0;
    if (status && !picks.length) status.textContent = "Şu an şarkı getirilemedi.";
  } catch {
    if (status) status.textContent = "Şarkılar getirilemedi, birazdan yeniden dene.";
  } finally {
    loading = false;
  }
}

section?.addEventListener("toggle", () => { if (section.open && !list?.children.length) load(); });
refresh?.addEventListener("click", load);
