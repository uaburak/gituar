// Sanatçı sayfası: şarkı listesini yazdıkça süzer (liste içi reklamlar eşleşme yoksa gizlenir).
import { turkeyNormalized } from "@shared/turkish";
const input = document.getElementById("song-filter") as HTMLInputElement | null;
const list = document.getElementById("artist-songs");
const empty = document.getElementById("filter-empty");
if (input && list) {
  const rows = [...list.querySelectorAll<HTMLAnchorElement>(".row")].map((el) => ({ el, key: turkeyNormalized(el.querySelector(".row-title")?.textContent ?? "") }));
  const ads = [...list.querySelectorAll<HTMLElement>(".ad-slot")];
  input.addEventListener("input", () => {
    const q = turkeyNormalized(input.value.trim());
    let visible = 0;
    for (const r of rows) { const show = !q || r.key.includes(q); r.el.hidden = !show; if (show) visible++; }
    for (const ad of ads) ad.hidden = Boolean(q);
    if (empty) empty.hidden = visible > 0;
  });
}
