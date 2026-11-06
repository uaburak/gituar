// Akor diyagramı SVG'si (ChordDiagram.astro ile aynı çizim); tarayıcıda şarkı kâğıdındaki akor balonu kullanır.
import type { Shape } from "./chord-theory.ts";

export function chordSvg(shape: Shape, title: string): string {
  const played = shape.frets.filter((f) => f > 0);
  const minFret = played.length ? Math.min(...played) : 1;
  const maxFret = played.length ? Math.max(...played) : 1;
  const start = maxFret <= 5 ? 1 : minFret;
  const W = 100, H = 120, left = 14, top = 22, sx = 14.4, sy = 18;
  const x = (s: number) => left + s * sx;
  const y = (f: number) => top + (f - start + 0.5) * sy;
  const barre = shape.barre && shape.barre >= start ? shape.barre : undefined;
  const barreStrings = barre ? shape.frets.map((f, i) => (f === barre ? i : -1)).filter((i) => i >= 0) : [];
  let out = `<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="${title}">`;
  out += start === 1
    ? `<rect x="${x(0)}" y="${top - 3}" width="${x(5) - x(0)}" height="3" class="cd-nut"/>`
    : `<text x="${left - 4}" y="${y(start) + 4}" class="cd-fret" text-anchor="end">${start}</text>`;
  for (let i = 0; i < 6; i++) out += `<line x1="${x(0)}" x2="${x(5)}" y1="${top + i * sy}" y2="${top + i * sy}" class="cd-line"/>`;
  for (let s = 0; s < 6; s++) out += `<line x1="${x(s)}" x2="${x(s)}" y1="${top}" y2="${top + 5 * sy}" class="cd-line"/>`;
  if (barre && barreStrings.length > 1) {
    const a = barreStrings[0], b = barreStrings[barreStrings.length - 1];
    out += `<rect x="${x(a) - 5}" y="${y(barre) - 5}" width="${x(b) - x(a) + 10}" height="10" rx="5" class="cd-dot"/>`;
  }
  shape.frets.forEach((f, s) => {
    if (f === -1) out += `<text x="${x(s)}" y="${top - 7}" class="cd-mark" text-anchor="middle">×</text>`;
    else if (f === 0) out += `<circle cx="${x(s)}" cy="${top - 10}" r="3.2" class="cd-open"/>`;
    else if (!(barre && f === barre && barreStrings.length > 1)) out += `<circle cx="${x(s)}" cy="${y(f)}" r="5" class="cd-dot"/>`;
  });
  return out + `</svg>`;
}
