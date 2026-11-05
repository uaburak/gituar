// Türkçe metin yardımcıları — iOS'taki TurkishText.swift ile birebir aynı kurallar.

const FOLD: Record<string, string> = {
  ç: "c", Ç: "c", ğ: "g", Ğ: "g", ı: "i", İ: "i", ö: "o", Ö: "o", ş: "s", Ş: "s", ü: "u", Ü: "u",
};

/** Arama için normalize eder: küçük harf, Türkçe karakterler ASCII'ye (ç→c, ı→i …). */
export function turkeyNormalized(input: string): string {
  let out = "";
  let needsFolding = false;
  for (const ch of input) {
    const code = ch.codePointAt(0) ?? 0;
    if (code >= 65 && code <= 90) out += String.fromCharCode(code + 32);
    else if (FOLD[ch] !== undefined) out += FOLD[ch];
    else {
      if (code > 127) needsFolding = true;
      out += ch;
    }
  }
  if (!needsFolding) return out;
  return out.toLocaleLowerCase("tr-TR").normalize("NFD").replace(/[̀-ͯ]/g, "");
}

/** URL parçası: "Barış Manço" → "baris-manco". Repertuarım'daki /ara/ kuralıyla uyumlu. */
export function slugify(input: string): string {
  const s = turkeyNormalized(input)
    .replace(/[''"’?!,;.:_+()[\]&/\\]/g, " ")
    .replace(/[^a-z0-9 -]+/g, "")
    .trim()
    .replace(/[\s]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
  return s || "x";
}

/** Türkçe alfabe sırası (ç, ğ, ı, ö, ş, ü doğru yerde). */
export function compareTurkish(a: string, b: string): number {
  return a.localeCompare(b, "tr-TR", { sensitivity: "base" });
}

export interface Searchable {
  songName: string;
  artist: string;
}

/**
 * Şarkı adı ve sanatçı üzerinde çok kelimeli arama ("sezen gülümse").
 * ranked=true: sorguyla başlayanlar öne, kalanlar ada göre; false: liste sırası korunur.
 */
export function searchSongs<T extends Searchable>(items: readonly T[], query: string, ranked = false): T[] {
  const words = turkeyNormalized(query).split(/\s+/).filter(Boolean);
  if (words.length === 0) return [...items];
  const full = words.join(" ");
  const matches: { item: T; name: string; rank: number }[] = [];
  for (const item of items) {
    const name = turkeyNormalized(item.songName);
    const artist = turkeyNormalized(item.artist);
    if (!words.every((w) => name.includes(w) || artist.includes(w))) continue;
    const rank = name.startsWith(full) ? 0 : artist.startsWith(full) ? 1 : 2;
    matches.push({ item, name, rank });
  }
  if (!ranked) return matches.map((m) => m.item);
  return matches
    .sort((x, y) => (x.rank !== y.rank ? x.rank - y.rank : x.name < y.name ? -1 : x.name > y.name ? 1 : 0))
    .map((m) => m.item);
}
