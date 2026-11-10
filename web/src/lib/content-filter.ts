// Kullanıcı içeriği için basit uygunsuz ifade filtresi — iOS ContentFilter.swift ile aynı liste ve kural
// (kelime başına eşleşme, Türkçe karakterler sadeleştirilerek). API de ayrıca denetler.
const BLOCKED = new Set([
  "amk", "aq", "amina", "aminakoyim", "amcik", "orospu", "orospucocugu", "pic", "pezevenk", "yarrak", "yarak",
  "siktir", "sikerim", "sikeyim", "sikik", "gavat", "kahpe", "ibne", "gotveren", "kaltak", "surtuk",
  "fuck", "fucking", "motherfucker", "shit", "bitch", "cunt", "pussy", "nigger", "faggot", "whore",
]);

function normalize(text: string): string {
  return text.toLocaleLowerCase("tr-TR").replace(/ı/g, "i").replace(/ğ/g, "g").replace(/ü/g, "u").replace(/ş/g, "s").replace(/ö/g, "o").replace(/ç/g, "c");
}

/** Metinlerde engelli bir kelime varsa ilkini döndürür. */
export function firstObjectionableWord(...texts: string[]): string | null {
  for (const t of texts) {
    for (const w of normalize(t).split(/[^\p{L}]+/u)) if (BLOCKED.has(w)) return w;
  }
  return null;
}
