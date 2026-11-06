// Ana sayfa: resimli "Editörün Seçimleri" kartındaki liste sayısı.
import { editorPicks } from "../lib/editor-picks.ts";
const el = document.getElementById("editor-count");
editorPicks().then((picks) => { if (el && picks.length) el.textContent = `${picks.length} özel liste`; });
