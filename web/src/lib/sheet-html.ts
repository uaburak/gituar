// Şarkı içeriğini SEO dostu, transpoze edilebilir HTML'e çevirir (build zamanı).
import { parse, chordSpans } from "@shared/chords";
import { escapeHtml } from "./html.ts";

export function sheetHtml(content: string): string {
  return parse(content)
    .map((line) => {
      if (!line.isChordLine) return `<span class="line">${escapeHtml(line.text)}\n</span>`;
      const spans = chordSpans(line.text);
      let html = "";
      let cursor = 0;
      for (const sp of spans) {
        html += escapeHtml(line.text.slice(cursor, sp.start));
        html += `<b class="chord">${escapeHtml(sp.chord)}</b>`;
        cursor = sp.end;
      }
      html += escapeHtml(line.text.slice(cursor));
      return `<span class="line" data-c="1">${html}\n</span>`;
    })
    .join("");
}
