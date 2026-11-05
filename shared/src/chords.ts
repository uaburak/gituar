// Akor satırı tespiti ve transpoze — iOS'taki ChordTransposer.swift'in birebir portu.
// Saf fonksiyonlar; tarayıcıda ve Node'da çalışır.

export interface SheetLine {
  id: number;
  text: string;
  isChordLine: boolean;
}

export interface ParsedChord {
  root: string;
  quality: string;
  bass: string | null;
}

/** Ton seçicide gösterilen notalar. */
export const selectableKeys = ["C", "C#", "Db", "D", "D#", "Eb", "E", "F", "F#", "Gb", "G", "G#", "Ab", "A", "A#", "Bb", "B"];

const sharpScale = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
const flatScale = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"];
const semitones: Record<string, number> = {
  C: 0, "B#": 0, "C#": 1, Db: 1, D: 2, "D#": 3, Eb: 3, E: 4, Fb: 4,
  F: 5, "E#": 5, "F#": 6, Gb: 6, G: 7, "G#": 8, Ab: 8, A: 9, "A#": 10, Bb: 10,
  B: 11, Cb: 11,
};
const qualityKeywords = ["maj", "min", "dim", "aug", "sus", "add"];
const separatorChars = "-–—,|()[]";

export function parse(content: string): SheetLine[] {
  return content
    .replace(/\r\n/g, "\n")
    .split("\n")
    .map((text, id) => ({ id, text, isChordLine: isChordLine(text) }));
}

/** "C#m" → "C#". Nota ile başlamıyorsa "C". */
export function rootNote(key: string): string {
  const chars = [...key.trim()];
  const cursor = { i: 0 };
  return readNote(chars, cursor) ?? "C";
}

/** Orijinal tondan hedef tona en kısa yarım ses farkı (−5…+6). */
export function semitoneOffset(originalKey: string, targetRoot: string): number {
  const from = semitones[rootNote(originalKey)];
  const to = semitones[targetRoot];
  if (from === undefined || to === undefined) return 0;
  const up = (((to - from) % 12) + 12) % 12;
  return up > 6 ? up - 12 : up;
}

/** Hedef ton bemollü yazılıyorsa (Bb, Eb… ya da F / Dm, Gm, Cm, Fm) akorlar da bemolle yazılır. */
export function prefersFlats(targetRoot: string, originalKey: string): boolean {
  if (targetRoot.endsWith("b")) return true;
  if (targetRoot.endsWith("#")) return false;
  const trimmed = originalKey.trim();
  const quality = trimmed.slice(rootNote(trimmed).length);
  const isMinor = quality.startsWith("m") && !quality.startsWith("maj");
  return isMinor ? ["D", "G", "C", "F"].includes(targetRoot) : targetRoot === "F";
}

export function isChordLine(line: string): boolean {
  const trimmed = line.trim();
  if (!trimmed) return false;
  const lowered = trimmed.toLowerCase();
  if (lowered.startsWith("x") || lowered.includes("intro")) return true;
  // Tab satırları (e|---0---|) akor satırı değildir
  if (trimmed.includes("--") || trimmed.includes("|-")) return false;
  const tokens = trimmed.split(/[\s\-–—,|()[\]]+/).filter(Boolean);
  if (tokens.length === 0) return false;
  const chordCount = tokens.filter((t) => parseChord(t) !== null).length;
  return chordCount / tokens.length >= 0.5;
}

/**
 * Satırdaki akorları `offset` yarım ses kaydırır. Akor olmayan kelimelere ("Nakarat:", "x2") dokunmaz;
 * akor uzayıp kısaldığında boşlukları ayarlayarak sözlerle hizayı korur.
 */
export function transpose(line: string, offset: number, preferFlats = false): string {
  const shift = ((offset % 12) + 12) % 12;
  if (shift === 0) return line;

  let result = "";
  let token = "";
  let spaceRun = 0;
  let debt = 0; // > 0: akor uzadı, sonraki boşluklardan düş · < 0: kısaldı, boşluk ekle

  const flushToken = () => {
    if (!token) return;
    const chord = parseChord(token);
    if (chord) {
      const transposed = transposedChord(chord, shift, preferFlats);
      debt += transposed.length - token.length;
      result += transposed;
    } else {
      result += token;
    }
    token = "";
  };

  const flushSpaces = (atLineEnd = false) => {
    if (spaceRun <= 0) return;
    let count = spaceRun;
    if (debt > 0) {
      const cut = Math.min(debt, count - 1);
      count -= cut;
      debt -= cut;
    } else if (debt < 0 && !atLineEnd) {
      count -= debt;
      debt = 0;
    }
    result += " ".repeat(count);
    spaceRun = 0;
  };

  for (const ch of line) {
    if (ch === " ") {
      flushToken();
      spaceRun += 1;
    } else if (isSeparator(ch)) {
      flushToken();
      flushSpaces();
      result += ch;
    } else {
      flushSpaces();
      token += ch;
    }
  }
  flushToken();
  flushSpaces(true);
  return result;
}

/** Akor satırındaki akorları konumlarıyla verir (vurgulama için). */
export function chordSpans(line: string): { start: number; end: number; chord: string }[] {
  const spans: { start: number; end: number; chord: string }[] = [];
  const re = /[^\s\-–—,|()[\]]+/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(line)) !== null) {
    if (parseChord(m[0])) spans.push({ start: m.index, end: m.index + m[0].length, chord: m[0] });
  }
  return spans;
}

function transposedChord(chord: ParsedChord, shift: number, preferFlats: boolean): string {
  let out = transposeNote(chord.root, shift, preferFlats) + chord.quality;
  if (chord.bass) out += "/" + transposeNote(chord.bass, shift, preferFlats);
  return out;
}

function transposeNote(note: string, shift: number, preferFlats: boolean): string {
  const index = semitones[note];
  if (index === undefined) return note;
  return (preferFlats ? flatScale : sharpScale)[(index + shift) % 12];
}

function isSeparator(ch: string): boolean {
  return /\s/.test(ch) || separatorChars.includes(ch);
}

function isDigit(ch: string): boolean {
  return ch >= "0" && ch <= "9";
}

/** `cursor.i` konumundan bir nota (A–G + isteğe bağlı #/b) okur ve ilerler. */
function readNote(chars: string[], cursor: { i: number }): string | null {
  const c = chars[cursor.i];
  if (c === undefined || c < "A" || c > "G") return null;
  let note = c;
  cursor.i += 1;
  const next = chars[cursor.i];
  if (next === "#" || next === "b") {
    note += next;
    cursor.i += 1;
  }
  return note;
}

/** "C#m7", "Dsus4", "G7b9", "D/F#" gibi bir akoru parçalarına ayırır; akor değilse null. */
export function parseChord(token: string): ParsedChord | null {
  const chars = [...token];
  const cursor = { i: 0 };
  const root = readNote(chars, cursor);
  if (!root) return null;
  const qualityStart = cursor.i;

  while (cursor.i < chars.length) {
    const ch = chars[cursor.i];
    if (ch === "/") {
      const next = cursor.i + 1;
      // "C6/9" gibi sayısal ek
      if (next < chars.length && isDigit(chars[next])) {
        cursor.i = next;
        continue;
      }
      // "D/F#" gibi bas notası — akorun sonunda olmalı
      const bassCursor = { i: next };
      const bass = readNote(chars, bassCursor);
      if (!bass || bassCursor.i !== chars.length) return null;
      return { root, quality: chars.slice(qualityStart, cursor.i).join(""), bass };
    }
    const keyword = qualityKeywords.find((k) => chars.slice(cursor.i, cursor.i + k.length).join("") === k);
    if (keyword) {
      cursor.i += keyword.length;
    } else if ("mM+°ø".includes(ch) || isDigit(ch)) {
      cursor.i += 1;
    } else if ((ch === "#" || ch === "b") && cursor.i + 1 < chars.length && isDigit(chars[cursor.i + 1])) {
      cursor.i += 1; // b5, #9 gibi alterasyonlar
    } else {
      return null;
    }
  }
  return { root, quality: chars.slice(qualityStart).join(""), bass: null };
}
