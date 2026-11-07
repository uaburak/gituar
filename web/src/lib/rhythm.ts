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
