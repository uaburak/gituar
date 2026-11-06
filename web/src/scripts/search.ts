import { search, searchArtists, rowHtml, artistRowHtml } from "../lib/search-client.ts";

const input = document.getElementById("q") as HTMLInputElement;
const clearBtn = document.getElementById("q-clear") as HTMLButtonElement;
const results = document.getElementById("results")!;
const artistList = document.getElementById("artist-list")!;
const songSection = document.getElementById("song-results")!;
const artistSection = document.getElementById("artist-results")!;
const status = document.getElementById("search-status")!;
const moreBtn = document.getElementById("show-more") as HTMLButtonElement;
const popular = document.getElementById("popular");
const PAGE = 20;
let seq = 0;
let hits: Awaited<ReturnType<typeof search>> = [];
let shown = 0;

function renderMore() {
  const next = hits.slice(shown, shown + PAGE);
  results.insertAdjacentHTML("beforeend", next.map(rowHtml).join(""));
  shown += next.length;
  const left = hits.length - shown;
  moreBtn.hidden = left <= 0;
  moreBtn.textContent = `${left} şarkıyı daha göster`;
}

async function run() {
  const q = input.value.trim();
  const my = ++seq;
  clearBtn.hidden = !q;
  const url = new URL(location.href);
  if (q) url.searchParams.set("q", q); else url.searchParams.delete("q");
  history.replaceState(null, "", url);
  if (popular) popular.hidden = q.length >= 2;
  if (!q) { songSection.hidden = true; artistSection.hidden = true; status.textContent = 'Şarkı adı, sanatçı ya da ikisi birden: "sezen gülümse" gibi.'; return; }
  if (q.length < 2) { songSection.hidden = true; artistSection.hidden = true; status.textContent = "En az iki harf yaz…"; return; }
  status.textContent = "Aranıyor…";
  const [songs, artists] = await Promise.all([search(q, 500), searchArtists(q, 5)]);
  if (my !== seq) return;
  hits = songs; shown = 0; results.innerHTML = "";
  artistList.innerHTML = artists.map(artistRowHtml).join("");
  artistSection.hidden = artists.length === 0;
  songSection.hidden = songs.length === 0;
  renderMore();
  const total = songs.length + artists.length;
  status.textContent = total ? `${total >= 500 ? "500+" : total} sonuç` : "Sonuç yok. Sanatçı ya da şarkı adını kontrol et.";
}

const initial = new URL(location.href).searchParams.get("q") ?? "";
if (initial) input.value = initial;
input.addEventListener("input", run);
input.form?.addEventListener("submit", (e) => { e.preventDefault(); run(); });
moreBtn.addEventListener("click", renderMore);
clearBtn.addEventListener("click", () => { input.value = ""; input.focus(); run(); });
if (initial) run();
