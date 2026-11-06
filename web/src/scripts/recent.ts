// Ana sayfa "Son Çaldıklarım": şarkı sayfasının localStorage'a yazdığı son 20 şarkı (yalnızca bu tarayıcıda).
import { esc } from "../lib/search-client.ts";
const list = document.getElementById("recent-list");
const empty = document.getElementById("recent-empty");
let items: { p: string; a: string; s: string }[] = [];
try { items = JSON.parse(localStorage.getItem("gituar-recent") ?? "[]"); } catch {}
if (list && items.length) {
  list.innerHTML = items.map((i) => `<li><a class="row" href="${esc(i.p)}"><span class="rp-badge" aria-hidden="true">A</span><span class="rp-text"><span class="row-artist">${esc(i.a)} - </span><span class="row-title">${esc(i.s)}</span></span></a></li>`).join("");
  if (empty) empty.hidden = true;
}
