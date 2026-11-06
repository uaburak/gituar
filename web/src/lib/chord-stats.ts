// Katalog genelinde akor analizi (build zamanı, bir kez hesaplanır):
// şarkı başına sadeleştirilmiş akorlar, zorluk, kapo ile kolay çalma; akor başına şarkılar ve asıl yazım.
import { parse, chordSpans } from "@shared/chords";
import { catalog, catalogVersion, type CatalogSong } from "./catalog.ts";
import { minChordSongs } from "./catalog-rules.mjs";
import { simplifyChord, chordClass, chordSlug, isOpenChord, shiftedName, chordShapes, pitchClass } from "./chord-theory.ts";

export interface SongChords {
  /** Şarkıdaki yazımıyla, ilk görülme sırasıyla sadeleştirilmiş akorlar. */
  chords: { root: string; quality: string; name: string }[];
  /** Barre gerektiren (açık olmayan) akor sayısı. */
  barreCount: number;
  level: "kolay" | "orta" | "ileri";
  /** Açık akorlara inen en küçük kapo perdesi (1–7) ve o kapoda tutulacak akorlar; şarkı zaten açıksa yok. */
  capo?: { fret: number; shapes: string[] };
}

export interface ChordEntry {
  slug: string;
  root: string;
  quality: string;
  name: string;
  /** Aynı akorun diğer yazımları (A# ↔ Bb). */
  aliases: string[];
  songIds: string[];
}

interface Stats {
  bySong: Map<string, SongChords>;
  chords: ChordEntry[];
  bySlug: Map<string, ChordEntry>;
  slugByClass: Map<string, string>;
}

let cache: Stats | null = null;
let cacheVersion = -1;

function songChordNames(content: string): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const line of parse(content)) {
    if (!line.isChordLine) continue;
    for (const sp of chordSpans(line.text)) if (!seen.has(sp.chord)) { seen.add(sp.chord); out.push(sp.chord); }
  }
  return out;
}



export function chordStats(): Stats {
  if (cache && cacheVersion === catalogVersion()) return cache;
  cacheVersion = catalogVersion();
  const bySong = new Map<string, SongChords>();
  const classSongs = new Map<string, Set<string>>();
  const classSpellings = new Map<string, Map<string, number>>();

  for (const song of catalog().songs) {
    const seen = new Set<string>();
    const chords: SongChords["chords"] = [];
    for (const token of songChordNames(song.content)) {
      const c = simplifyChord(token);
      if (!c) continue;
      const cls = chordClass(c.root, c.quality);
      if (seen.has(cls)) continue;
      seen.add(cls);
      chords.push({ ...c, name: c.root + c.quality });
      if (!classSongs.has(cls)) classSongs.set(cls, new Set());
      classSongs.get(cls)!.add(song.id);
      if (!classSpellings.has(cls)) classSpellings.set(cls, new Map());
      const sp = classSpellings.get(cls)!;
      sp.set(c.root, (sp.get(c.root) ?? 0) + 1);
    }
    const barreCount = chords.filter((c) => !isOpenChord(c.root, c.quality)).length;
    const level: SongChords["level"] = chords.length === 0 ? "orta" : barreCount === 0 ? "kolay" : barreCount <= 2 ? "orta" : "ileri";
    let capo: SongChords["capo"];
    if (barreCount > 0 && chords.length > 0) {
      for (let k = 1; k <= 7; k++) {
        if (chords.every((c) => isOpenChord(...shiftRoot(c.root, c.quality, k)))) {
          capo = { fret: k, shapes: chords.map((c) => shiftedName(c.root, c.quality, k)) };
          break;
        }
      }
    }
    bySong.set(song.id, { chords, barreCount, level, capo });
  }

  const chords: ChordEntry[] = [];
  for (const [cls, songs] of classSongs) {
    const spellings = [...classSpellings.get(cls)!.entries()].sort((a, b) => b[1] - a[1]).map(([r]) => r);
    const quality = cls.split(":")[1];
    const root = spellings[0];
    if (chordShapes(root, quality).length === 0) continue;
    chords.push({ slug: chordSlug(root, quality), root, quality, name: root + quality, aliases: spellings.slice(1).map((r) => r + quality), songIds: [...songs] });
  }
  chords.sort((a, b) => b.songIds.length - a.songIds.length);
  const pages = chords.filter((c) => c.songIds.length >= minChordSongs());
  cache = {
    bySong,
    chords,
    bySlug: new Map(pages.map((c) => [c.slug, c])),
    slugByClass: new Map(pages.map((c) => [chordClass(c.root, c.quality), c.slug])),
  };
  return cache;
}

function shiftRoot(root: string, quality: string, down: number): [string, string] {
  const name = shiftedName(root, quality, down);
  return [name.slice(0, name.length - quality.length), quality];
}

/** Akor sözlüğünde sayfası olan akorlar (en az 20 şarkı), şarkı sayısına göre. */
export function chordPages(): ChordEntry[] {
  return [...chordStats().bySlug.values()];
}

/** Şarkıdaki bir akorun sözlük sayfası (varsa). */
export function chordHref(root: string, quality: string): string | undefined {
  const slug = chordStats().slugByClass.get(chordClass(root, quality));
  return slug ? `/akorlar/${slug}/` : undefined;
}

export function songChords(song: CatalogSong): SongChords {
  return chordStats().bySong.get(song.id) ?? { chords: [], barreCount: 0, level: "orta" };
}

export const LEVEL_LABEL: Record<SongChords["level"], string> = { kolay: "Kolay", orta: "Orta", ileri: "İleri" };

/** Yalnızca açık akorlarla çalınan şarkılar, akor sayısına göre (az → çok), aynı sayıda yeniler önce. */
export function easySongs(): CatalogSong[] {
  const st = chordStats();
  return catalog().songs
    .filter((s) => { const c = st.bySong.get(s.id); return c && c.level === "kolay" && c.chords.length >= 2; })
    .sort((a, b) => st.bySong.get(a.id)!.chords.length - st.bySong.get(b.id)!.chords.length || b.seq - a.seq);
}

export function capoEasySongs(): CatalogSong[] {
  const st = chordStats();
  return catalog().songs
    .filter((s) => st.bySong.get(s.id)?.capo)
    .sort((a, b) => st.bySong.get(a.id)!.capo!.fret - st.bySong.get(b.id)!.capo!.fret || b.seq - a.seq);
}

export { pitchClass };
