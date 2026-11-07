// Editörün seçimleri sayfası: tüm editör repertuarlarını kart olarak listeler.
import { editorPicks, pickCardHtml } from "../lib/editor-picks.ts";
import { esc } from "../lib/search-client.ts";
const grid = document.getElementById("editor-picks");
const status = document.getElementById("editor-status");
const meta = document.getElementById("editor-meta");
editorPicks().then((picks) => {
  if (!grid) return;
  grid.innerHTML = picks.map((p) => pickCardHtml(p, esc)).join("");
  if (meta) meta.textContent = "Gituar ekibinin hazırladığı repertuarlar.";
  if (status) status.textContent = picks.length ? "" : "Şu an listelenecek repertuar yok.";
});
