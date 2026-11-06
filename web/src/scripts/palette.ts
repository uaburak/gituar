// ⌘K / Ctrl+K / "/" ile her sayfada açılan arama paneli: şarkı + sanatçı, klavyeyle gezilir.
import { search, searchArtists, rowHtml, artistRowHtml, esc } from "../lib/search-client.ts";

const dialog = document.getElementById("palette") as HTMLDialogElement | null;
const input = document.getElementById("palette-q") as HTMLInputElement | null;
const results = document.getElementById("palette-results");
const allLink = document.getElementById("palette-all") as HTMLAnchorElement | null;
const kbd = document.getElementById("search-kbd");
const isMac = /Mac|iPhone|iPad/.test(navigator.platform);
if (kbd) kbd.textContent = isMac ? "⌘K" : "Ctrl K";

let active = -1;
let seq = 0;

function items(): HTMLAnchorElement[] { return results ? [...results.querySelectorAll<HTMLAnchorElement>("a.row")] : []; }
function setActive(i: number) {
  const list = items();
  if (!list.length) { active = -1; return; }
  active = (i + list.length) % list.length;
  list.forEach((el, k) => el.classList.toggle("active", k === active));
  list[active].scrollIntoView({ block: "nearest" });
}

async function render(q: string) {
  if (!results) return;
  const my = ++seq;
  const query = q.trim();
  if (allLink) allLink.href = query ? `/ara/?q=${encodeURIComponent(query)}` : "/ara/";
  if (!query) { results.innerHTML = `<div class="palette-empty">Şarkı adı, sanatçı ya da ikisi birden: "sezen gülümse" gibi.</div>`; active = -1; return; }
  const [songs, artists] = await Promise.all([search(query, 12), searchArtists(query, 3)]);
  if (my !== seq) return;
  if (!songs.length && !artists.length) { results.innerHTML = `<div class="palette-empty">"${esc(query)}" için sonuç yok.</div>`; active = -1; return; }
  results.innerHTML =
    (artists.length ? `<div class="palette-group">Sanatçılar</div><div class="list palette-list">${artists.map(artistRowHtml).join("")}</div>` : "") +
    (songs.length ? `<div class="palette-group">Şarkılar</div><div class="list palette-list">${songs.map(rowHtml).join("")}</div>` : "");
  setActive(0);
}

export function openPalette(initial = "") {
  if (!dialog || !input) { location.href = "/ara/"; return; }
  if (!dialog.open) dialog.showModal();
  input.value = initial;
  render(initial);
  input.focus();
  input.select();
}
function closePalette() { dialog?.close(); }

if (dialog && input) {
  input.addEventListener("input", () => render(input.value));
  input.addEventListener("keydown", (e) => {
    if (e.key === "ArrowDown") { e.preventDefault(); setActive(active + 1); }
    else if (e.key === "ArrowUp") { e.preventDefault(); setActive(active - 1); }
    else if (e.key === "Enter") {
      const list = items();
      e.preventDefault();
      if (active >= 0 && list[active]) location.href = list[active].href;
      else if (input.value.trim()) location.href = `/ara/?q=${encodeURIComponent(input.value.trim())}`;
    }
  });
  dialog.addEventListener("click", (e) => { if (e.target === dialog) closePalette(); });
  document.getElementById("palette-close")?.addEventListener("click", closePalette);
  for (const id of ["search-open", "search-open-mobile"]) document.getElementById(id)?.addEventListener("click", () => openPalette());
  document.addEventListener("keydown", (e) => {
    const target = e.target as HTMLElement | null;
    const typing = target && /^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName);
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") { e.preventDefault(); dialog.open ? closePalette() : openPalette(); return; }
    if (e.key === "/" && !typing && !e.metaKey && !e.ctrlKey && !e.altKey) { e.preventDefault(); openPalette(); }
  });
}
