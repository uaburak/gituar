// Ritim ve arpej desenleri: ölçüyü eşit parçalara (vuruş yerlerine) bölen dizi.
// Ritim: "↓ · ↓ ↑ · ↑ ↓ ↑" (ok = vuruş, · = es) ya da Repertuarım'daki gibi "A A YYAY" (A aşağı, Y yukarı, boşluk es).
// Arpej: "B 3 2 1 2 3" (B = akorun bas teli, 1 = ince E … 6 = kalın E, · = es).
export type Stroke = "down" | "up" | "mute" | null; // mute = kesme ("K"): teller susturularak vurulur
export type Pluck = number | "bass" | null; // 0 (kalın E) … 5 (ince E)

export const DEFAULT_RHYTHM = "↓ · ↓ ↑ · ↑ ↓ ↑";
export const DEFAULT_ARPEGGIO = "B 3 2 1 2 3 2 3";
export const DEFAULT_TEMPO = 90;

export function parseRhythm(input: string | undefined): Stroke[] {
  const s = (input ?? "").trim();
  if (!s) return parseRhythm(DEFAULT_RHYTHM);
  // Ok / nokta yazımı: boşlukla ayrılmış simgeler
  if (/[↓↑·]/.test(s)) {
    return s.split(/\s+/).flatMap((tok) => [...tok].map((c): Stroke => (c === "↓" ? "down" : c === "↑" ? "up" : /[KkX×]/.test(c) ? "mute" : null)));
  }
  // Harf yazımı: A/D = aşağı, Y/U = yukarı, diğer her şey (boşluk, -, x) es
  return [...s.toUpperCase()].map((c): Stroke => ("AD".includes(c) ? "down" : "YU".includes(c) ? "up" : "KX".includes(c) ? "mute" : null));
}

// PIMA (klasik gitar parmak yazımı): p = başparmak (bas tel), i = 3. tel, m = 2. tel, a = 1. tel
const PIMA: Record<string, Pluck> = { p: "bass", i: 3, m: 4, a: 5 };

export function parseArpeggio(input: string | undefined): Pluck[] {
  const raw = (input ?? "").trim();
  // "pimamiam", "Pima-tuş" gibi: yalnızca p/i/m/a harfleri alınır, kalanı yok sayılır
  const pima = raw.toLocaleLowerCase("tr-TR").split(/[^a-zçğıöşü]+/)[0] ?? "";
  if (pima && /^[pima]+$/.test(pima)) return [...pima].map((c) => PIMA[c]);
  const s = raw || DEFAULT_ARPEGGIO;
  return s.split(/[\s,-]+/).filter(Boolean).map((tok) => {
    if (/^b$/i.test(tok)) return "bass";
    const n = Number(tok);
    return n >= 1 && n <= 6 ? 6 - n : null; // 1 = ince E (5) … 6 = kalın E (0)
  });
}

/** Ölçüdeki vuruş sayısı (tartımın payı): "4/4" → 4, "3/4" → 3, "6/8" → 2 (iki uzun vuruş) */
export function beatsPerBar(meter: string | undefined): number {
  const m = /^(\d+)\/(\d+)$/.exec((meter ?? "").trim());
  if (!m) return 4;
  const [num, den] = [Number(m[1]), Number(m[2])];
  return den === 8 && num % 3 === 0 ? num / 3 : num;
}

export function tempoLabel(bpm: number): string {
  return bpm < 60 ? "Çok yavaş" : bpm < 80 ? "Yavaş" : bpm < 110 ? "Orta" : bpm < 140 ? "Hızlı" : "Çok hızlı";
}

/** Zaman çizelgesindeki bir akor: kâğıttaki öğesi, başladığı vuruş ve süresi (vuruş). */
export interface TimedChord { el: HTMLElement; start: number; beats: number }

/** Söz satırında yaklaşık bu kadar karakter bir ölçüye denk gelir (hece hızı; tahmin). */
export const CHARS_PER_BAR = 24;

/** Kesirli süreleri tam vuruşa yuvarlar: her biri en az `min`, toplam `total` (en büyük kalan yöntemi). */
function quantize(raw: number[], total: number, min = 1): number[] {
  const out = raw.map((x) => Math.max(min, Math.floor(x)));
  let left = total - out.reduce((a, b) => a + b, 0);
  const order = raw.map((x, i) => [x - Math.floor(x), i] as const).sort((a, b) => b[0] - a[0]);
  for (let k = 0; left > 0; k = (k + 1) % order.length) { out[order[k][1]]++; left--; }
  for (let k = out.length - 1; left < 0 && k >= 0; k--) { while (left < 0 && out[k] > min) { out[k]--; left++; } }
  return out;
}

/**
 * Kâğıttaki akorların süresini konumlarından tahmin eder (veri gerektirmez):
 * - Sözsüz akor satırı (giriş, ara): her akor bir ölçü.
 * - Sözlü satır: satır ~CHARS_PER_BAR karakter başına bir ölçü sürer (en az 1); akorlar bu süreyi sözdeki
 *   yerleri arasındaki mesafeye göre paylaşır, tam vuruşa yuvarlanır (her akor en az bir vuruş).
 *   İlk akor satır başında değilse aradaki süre önceki akora eklenir (önceki akor çalmaya devam eder).
 */
export function chordTimeline(pre: HTMLElement, beatsPerBar: number): TimedChord[] {
  const lines = [...pre.querySelectorAll<HTMLElement>(".line")];
  const out: TimedChord[] = [];
  let beat = 0;
  lines.forEach((line, i) => {
    const chords: { el: HTMLElement; col: number; len: number }[] = [];
    let col = 0;
    for (const node of line.childNodes) {
      const text = node.textContent ?? "";
      if (node instanceof HTMLElement && node.classList.contains("chord")) chords.push({ el: node, col, len: text.length });
      col += text.length;
    }
    if (!chords.length) return;
    const next = lines[i + 1];
    const lyric = next && !next.dataset.c ? (next.textContent ?? "").replace(/\s+$/, "") : "";
    if (!lyric.trim()) {
      for (const c of chords) { out.push({ el: c.el, start: beat, beats: beatsPerBar }); beat += beatsPerBar; }
      return;
    }
    const last = chords[chords.length - 1];
    const span = Math.max(lyric.length, last.col + last.len, 1);
    const total = Math.max(1, Math.round(span / CHARS_PER_BAR)) * beatsPerBar;
    const lead = (chords[0].col / span) * total;
    const raw = chords.map((c, k) => (((k + 1 < chords.length ? chords[k + 1].col : span) - c.col) / span) * total);
    // Satır başındaki boşluk önceki akora (varsa) eklenir; yoksa ilk akora
    const prev = out[out.length - 1];
    const leadBeats = prev ? Math.min(Math.round(lead), Math.max(0, total - chords.length)) : 0;
    const beats = quantize(prev ? raw : raw.map((x, k) => (k === 0 ? x + lead : x)), total - leadBeats);
    if (prev && leadBeats) { prev.beats += leadBeats; beat += leadBeats; }
    chords.forEach((c, k) => { out.push({ el: c.el, start: beat, beats: beats[k] }); beat += beats[k]; });
  });
  return out;
}
