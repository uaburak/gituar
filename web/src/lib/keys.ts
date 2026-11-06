// Ton sayfaları: ton adı → URL parçası, Türkçe ad ve tonun diyatonik akorları (SEO içeriği için).
const NOTES_SHARP = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
const NOTES_FLAT = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"];
const TR_NAMES: Record<string, string> = { C: "Do", D: "Re", E: "Mi", F: "Fa", G: "Sol", A: "La", B: "Si" };

export function parseKey(key: string): { root: string; minor: boolean } | null {
  const m = /^([A-G])(#|b)?(m)?$/.exec(key.trim());
  if (!m) return null;
  return { root: m[1] + (m[2] ?? ""), minor: Boolean(m[3]) };
}

export function keySlug(key: string): string {
  const k = parseKey(key);
  if (!k) return "";
  const root = k.root[0].toLowerCase() + (k.root.endsWith("#") ? "-diyez" : k.root.endsWith("b") ? "-bemol" : "");
  return root + (k.minor ? "-minor" : "");
}

/** "C#m" → "Do diyez minör" */
export function keyTurkish(key: string): string {
  const k = parseKey(key);
  if (!k) return key;
  const acc = k.root.endsWith("#") ? " diyez" : k.root.endsWith("b") ? " bemol" : "";
  return `${TR_NAMES[k.root[0]]}${acc} ${k.minor ? "minör" : "majör"}`;
}

/** Tonun diyatonik akorları: majör I ii iii IV V vi, minör i III iv v VI VII. */
export function diatonicChords(key: string): string[] {
  const k = parseKey(key);
  if (!k) return [];
  const useFlat = k.root.endsWith("b") || (!k.minor && k.root === "F") || (k.minor && ["D", "G", "C", "F"].includes(k.root));
  const scale = useFlat ? NOTES_FLAT : NOTES_SHARP;
  const idx = NOTES_SHARP.indexOf(k.root) >= 0 ? NOTES_SHARP.indexOf(k.root) : NOTES_FLAT.indexOf(k.root);
  const n = (semi: number) => scale[(idx + semi + 12) % 12];
  return k.minor
    ? [n(0) + "m", n(3), n(5) + "m", n(7) + "m", n(8), n(10)]
    : [n(0), n(2) + "m", n(4) + "m", n(5), n(7), n(9) + "m"];
}
