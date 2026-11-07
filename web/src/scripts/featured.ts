// Ana sayfa "Öne Çıkanlar": sunucu editörün seçimlerini alamadıysa tarayıcıda yükler ve şarkılarını listeler.
import { editorPicks } from "../lib/editor-picks.ts";
import { songsByIds, rowHtml, esc } from "../lib/search-client.ts";
import { FIREBASE_CONFIG } from "../lib/site.ts";

const box = document.getElementById("editor-songs");
const status = document.getElementById("editor-status");
const section = document.getElementById("featured") as HTMLDetailsElement | null;
let started = false;

async function songIdsOf(id: string): Promise<string[]> {
  const url = `https://firestore.googleapis.com/v1/projects/${FIREBASE_CONFIG.projectId}/databases/(default)/documents/public-repertoires/${encodeURIComponent(id)}?key=${FIREBASE_CONFIG.apiKey}`;
  const doc = await fetch(url).then((r) => r.json());
  return (doc.fields?.songIds?.arrayValue?.values ?? []).map((v: { stringValue?: string }) => v.stringValue ?? "").filter(Boolean);
}

async function load() {
  if (!box || started) return;
  started = true;
  try {
    const picks = (await editorPicks()).slice(0, 6);
    const groups = await Promise.all(picks.map(async (p) => ({ name: p.name, songs: await songsByIds(await songIdsOf(p.id)) })));
    const filled = groups.filter((g) => g.songs.length);
    box.innerHTML = filled.map((g) => `${filled.length > 1 ? `<h3 class="rp-group">${esc(g.name)}</h3>` : ""}<ul class="rp-list">${g.songs.map(rowHtml).join("")}</ul>`).join("");
    if (status) { status.hidden = filled.length > 0; status.textContent = "Şu an öne çıkan şarkı yok."; }
  } catch {
    if (status) status.textContent = "Şarkılar yüklenemedi.";
  }
}
section?.addEventListener("toggle", () => { if (section.open) load(); });
