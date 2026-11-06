// Akor kuramı (build zamanı ve sayfalarda): akor adını sadeleştirme, eşsesli yazımlar, notalar,
// gitar tutuşu (açık akor tablosu + E/A biçimli barre üretimi), Türkçe ad ve URL parçası.
import { parseChord } from "@shared/chords";

export const SHARPS = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
export const FLATS = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"];
const PC: Record<string, number> = {
  C: 0, "B#": 0, "C#": 1, Db: 1, D: 2, "D#": 3, Eb: 3, E: 4, Fb: 4, F: 5, "E#": 5,
  "F#": 6, Gb: 6, G: 7, "G#": 8, Ab: 8, A: 9, "A#": 10, Bb: 10, B: 11, Cb: 11,
};
const TR: Record<string, string> = { C: "Do", D: "Re", E: "Mi", F: "Fa", G: "Sol", A: "La", B: "Si" };

/** Desteklenen akor nitelikleri: aralıklar (kökten yarım ses) ve Türkçe ad. */
export const QUALITIES: Record<string, { intervals: number[]; tr: string }> = {
  "": { intervals: [0, 4, 7], tr: "majör" },
  m: { intervals: [0, 3, 7], tr: "minör" },
  "7": { intervals: [0, 4, 7, 10], tr: "dominant yedili (7)" },
  m7: { intervals: [0, 3, 7, 10], tr: "minör yedili (m7)" },
  maj7: { intervals: [0, 4, 7, 11], tr: "majör yedili (maj7)" },
  sus2: { intervals: [0, 2, 7], tr: "sus2" },
  sus4: { intervals: [0, 5, 7], tr: "sus4" },
  "7sus4": { intervals: [0, 5, 7, 10], tr: "7sus4" },
  dim: { intervals: [0, 3, 6], tr: "eksik (dim)" },
  m7b5: { intervals: [0, 3, 6, 10], tr: "yarım eksik (m7b5)" },
  aug: { intervals: [0, 4, 8], tr: "artık (aug)" },
  "6": { intervals: [0, 4, 7, 9], tr: "altılı (6)" },
  m6: { intervals: [0, 3, 7, 9], tr: "minör altılı (m6)" },
  add9: { intervals: [0, 4, 7, 2], tr: "add9" },
  "9": { intervals: [0, 4, 7, 10, 2], tr: "dokuzlu (9)" },
};

/** "Amin" → "Am", "CM7" → "Cmaj7", "D/F#" → "D", "Bbsus" → "Bbsus4". Desteklenmeyen nitelikte null. */
export function simplifyChord(token: string): { root: string; quality: string } | null {
  const p = parseChord(token);
  if (!p) return null;
  let q = p.quality;
  const map: Record<string, string> = {
    min: "m", mi: "m", "-": "m", maj: "", M: "", M7: "maj7", Maj7: "maj7", ma7: "maj7", min7: "m7", "m7(b5)": "m7b5", "ø": "m7b5", "ø7": "m7b5",
    "°": "dim", dim7: "dim", "°7": "dim", "+": "aug", sus: "sus4", "7sus": "7sus4", add2: "add9", "2": "sus2", "4": "sus4",
    min6: "m6", maj9: "maj7", m9: "m7", madd9: "m", "6/9": "6", "5": "",
  };
  if (q in map) q = map[q];
  if (!(q in QUALITIES)) return null;
  if (!(p.root in PC)) return null;
  return { root: p.root, quality: q };
}

export function pitchClass(note: string): number {
  return PC[note] ?? -1;
}

export function chordName(root: string, quality: string): string {
  return root + quality;
}

/** Eşsesli yazımların ortak anahtarı: "Bbm" ve "A#m" → "10:m". */
export function chordClass(root: string, quality: string): string {
  return `${PC[root]}:${quality}`;
}

export function noteTurkish(note: string): string {
  const acc = note.endsWith("#") ? " diyez" : note.endsWith("b") && note.length === 2 ? " bemol" : "";
  return `${TR[note[0]] ?? note}${acc}`;
}

export function chordTurkish(root: string, quality: string): string {
  return `${noteTurkish(root)} ${QUALITIES[quality]?.tr ?? quality}`;
}

/** URL parçası: "Am" → "am", "F#m" → "f-diyez-m", "Bb7" → "b-bemol-7", "Cmaj7" → "cmaj7". */
export function chordSlug(root: string, quality: string): string {
  const r = root[0].toLowerCase() + (root.endsWith("#") ? "-diyez" : root.length === 2 && root.endsWith("b") ? "-bemol" : "");
  const q = quality.toLowerCase();
  return root.length === 2 && q ? `${r}-${q}` : `${r}${q}`;
}

/** Akorun notaları, kök yazımına uygun diyez/bemol ile. */
export function chordNotes(root: string, quality: string): string[] {
  const flats = root.length === 2 && root.endsWith("b") || root === "F";
  const scale = flats ? FLATS : SHARPS;
  const base = PC[root];
  return (QUALITIES[quality]?.intervals ?? []).map((i) => scale[(base + i) % 12]);
}

// ---------- Tutuşlar ----------

/** Telden tele (6. kalın tel → 1. ince tel) perde; -1 çalınmaz, 0 açık tel. */
export interface Shape { frets: number[]; barre?: number; name: string }

const OPEN: Record<string, string> = {
  C: "x32010", D: "xx0232", E: "022100", G: "320003", A: "x02220",
  Am: "x02210", Em: "022000", Dm: "xx0231",
  A7: "x02020", B7: "x21202", C7: "x32310", D7: "xx0212", E7: "020100", G7: "320001",
  Am7: "x02010", Em7: "022030", Dm7: "xx0211",
  Asus2: "x02200", Asus4: "x02230", Dsus2: "xx0230", Dsus4: "xx0233", Esus4: "022200",
  Cmaj7: "x32000", Fmaj7: "xx3210", Amaj7: "x02120", Dmaj7: "xx0222", Gmaj7: "320002",
  Cadd9: "x32030", A7sus4: "x02030", E7sus4: "020200", D6: "xx0202", A6: "x02222", Am6: "x02212", Em6: "022020",
  Bdim: "x2343x", Edim: "0120xx",
};
/** Açık (barresiz) sayılan akorlar: kolay şarkı ve kapo hesabı bunlara göre yapılır. */
export const OPEN_CHORDS = new Set(Object.keys(OPEN).filter((k) => !k.endsWith("dim")));

/** Kök 6. telde (E biçimi) ve 5. telde (A biçimi) barre kalıpları: kökten göreli perdeler. */
const E_FORM: Record<string, (number | null)[]> = {
  "": [0, 2, 2, 1, 0, 0], m: [0, 2, 2, 0, 0, 0], "7": [0, 2, 0, 1, 0, 0], m7: [0, 2, 0, 0, 0, 0],
  sus4: [0, 2, 2, 2, 0, 0], "7sus4": [0, 2, 0, 2, 0, 0], m6: [0, 2, 2, 0, 2, 0], "6": [0, 2, 2, 1, 2, 0],
};
const A_FORM: Record<string, (number | null)[]> = {
  "": [null, 0, 2, 2, 2, 0], m: [null, 0, 2, 2, 1, 0], "7": [null, 0, 2, 0, 2, 0], m7: [null, 0, 2, 0, 1, 0],
  maj7: [null, 0, 2, 1, 2, 0], sus2: [null, 0, 2, 2, 0, 0], sus4: [null, 0, 2, 2, 3, 0], "7sus4": [null, 0, 2, 0, 3, 0],
  dim: [null, 0, 1, 2, 1, null], m7b5: [null, 0, 1, 0, 1, null], aug: [null, 0, 3, 2, 2, null],
  "6": [null, 0, 2, 2, 2, 2], m6: [null, 0, 2, 2, 1, 2], add9: [null, 0, 2, 4, 0, 0], "9": [null, 0, -1, 0, 0, 0],
};

function parseFrets(s: string): number[] {
  return [...s].map((c) => (c === "x" ? -1 : Number(c)));
}

function barreShape(form: (number | null)[], fret: number, name: string): Shape | null {
  if (form.some((x) => x !== null && fret + x < 0)) return null;
  const frets = form.map((x) => (x === null ? -1 : fret + x));
  return { frets, barre: fret >= 1 ? fret : undefined, name };
}

/** Akorun tutuşları: önce açık tutuş (varsa), sonra E ve A biçimli barre (perdeye göre sıralı). */
export function chordShapes(root: string, quality: string): Shape[] {
  const pc = PC[root];
  const open: Shape[] = [];
  for (const spelling of [SHARPS[pc], FLATS[pc]]) {
    const o = OPEN[spelling + quality];
    if (o) { open.push({ frets: parseFrets(o), name: "Açık tutuş" }); break; }
  }
  const barres: Shape[] = [];
  const eFret = (pc - 4 + 12) % 12 || 12;
  const aFret = (pc - 9 + 12) % 12 || 12;
  if (E_FORM[quality]) { const s = barreShape(E_FORM[quality], eFret, `Barre, ${eFret}. perde (kök 6. telde)`); if (s) barres.push(s); }
  if (A_FORM[quality]) { const s = barreShape(A_FORM[quality], aFret, `Barre, ${aFret}. perde (kök 5. telde)`); if (s) barres.push(s); }
  // Açık tutuş önce, sonra en alçak perdedeki barre
  return [...open, ...barres.sort((x, y) => (x.barre ?? 0) - (y.barre ?? 0))];
}

/** Açık akor mu? (kapo/kolay hesabı) — eşsesli yazımlar da sayılır. */
export function isOpenChord(root: string, quality: string): boolean {
  const pc = PC[root];
  return OPEN_CHORDS.has(SHARPS[pc] + quality) || OPEN_CHORDS.has(FLATS[pc] + quality);
}

/** Kapo k ile hangi tutuşların çalınacağı: akorlar k yarım ses aşağı. */
export function shiftedName(root: string, quality: string, down: number): string {
  const pc = (PC[root] - down + 12) % 12;
  const sharp = SHARPS[pc] + quality;
  return OPEN_CHORDS.has(sharp) ? sharp : (OPEN_CHORDS.has(FLATS[pc] + quality) ? FLATS[pc] + quality : sharp);
}
