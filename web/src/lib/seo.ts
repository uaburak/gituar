// SEO yardımcıları: başlık/meta şablonları, kullanılan akorlar ve JSON-LD üreticileri. Yalnızca build zamanı.
// Anahtar kelime haritası ve şablon kararları: docs/SEO.md
import { parse, chordSpans } from "@shared/chords";
import { artistPath, songPath, type ArtistGroup } from "@shared/catalog";
import type { CatalogSong } from "@shared/types";
import { SITE_NAME, APP_STORE_URL, APP_STORE_ID } from "./site.ts";

/** Base.astro her başlığın sonuna bunu ekler; sığdırma hesabı bu ekle birlikte yapılır. */
export const TITLE_SUFFIX = ` · ${SITE_NAME}`;
export const TITLE_MAX = 60;
export const DESC_MAX = 155;

export function siteUrl(site: URL | undefined): string {
  return (site ?? new URL("https://gituar.com")).href.replace(/\/$/, "");
}

/** Adaylardan (uzundan kısaya), son ekle birlikte 60 karaktere sığan ilkini seçer; hiçbiri sığmazsa en kısasını. */
export function fitTitle(candidates: string[]): string {
  for (const c of candidates) if (c.length + TITLE_SUFFIX.length <= TITLE_MAX) return c;
  return candidates[candidates.length - 1];
}

/** İçerikteki akor satırlarından benzersiz akorlar, ilk görülme sırasıyla (shared/chords tespiti). */
export function usedChords(content: string, max = 12): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const line of parse(content)) {
    if (!line.isChordLine) continue;
    for (const sp of chordSpans(line.text)) {
      if (seen.has(sp.chord)) continue;
      seen.add(sp.chord);
      out.push(sp.chord);
      if (out.length >= max) return out;
    }
  }
  return out;
}

/**
 * Sözlerde Türkçeye özgü harf (ç ğ ı ö ş ü) yeterince geçiyorsa eser Türkçe sayılır.
 * Katalogda yabancı şarkılar da var; onlara inLanguage yazılmaz (yanlış veri basmamak için).
 */
export function looksTurkish(text: string): boolean {
  return (text.match(/[çğıöşüÇĞİÖŞÜ]/g)?.length ?? 0) >= 3;
}

// ---------- Şarkı sayfası ----------

export function songTitle(song: CatalogSong): string {
  const base = `${song.songName} Akorları – ${song.artist}`;
  if (!song.originalKey) return base;
  return fitTitle([`${base} | Gitar Akoru, Ton ${song.originalKey}`, `${base} | Ton ${song.originalKey}`, base]);
}

export function songDescription(song: CatalogSong, chords: string[]): string {
  const key = song.originalKey ? `, orijinal ton ${song.originalKey}` : "";
  const lead = `${song.songName} akorları – ${song.artist} şarkısının gitar akorları${key}.`;
  const tail = "Transpoze, kapo ve otomatik kaydırma ile çal.";
  const list = [...chords];
  while (list.length) {
    const d = `${lead} Akorlar: ${list.join(", ")}. ${tail}`;
    if (d.length <= DESC_MAX) return d;
    list.pop();
  }
  const d = `${lead} ${tail}`;
  return d.length <= DESC_MAX ? d : lead;
}

export interface Crumb {
  name: string;
  /** Son öğede (geçerli sayfa) boş bırakılır. */
  path?: string;
}

export function breadcrumbJsonLd(base: string, crumbs: Crumb[]) {
  return {
    "@type": "BreadcrumbList",
    itemListElement: crumbs.map((c, i) => ({
      "@type": "ListItem",
      position: i + 1,
      name: c.name,
      ...(c.path ? { item: base + c.path } : {}),
    })),
  };
}

export function songCrumbs(song: CatalogSong): Crumb[] {
  return [
    { name: "Ana sayfa", path: "/" },
    { name: "Sanatçılar", path: "/sanatcilar/" },
    { name: song.artist, path: artistPath(song.artistSlug) },
    { name: `${song.songName} akorları` },
  ];
}

/**
 * MusicComposition: eserin adı; `recordedAs` → MusicRecording → `byArtist` → MusicGroup.
 * Katalogdaki "artist" seslendiren sanatçıdır, bestecisi bilinmez; o yüzden `composer` yazılmaz.
 */
export function songJsonLd(song: CatalogSong, base: string) {
  const url = base + songPath(song);
  const artistUrl = base + artistPath(song.artistSlug);
  const artist = { "@type": "MusicGroup", "@id": `${artistUrl}#artist`, name: song.artist, url: artistUrl };
  return {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "MusicComposition",
        "@id": `${url}#composition`,
        name: song.songName,
        url,
        mainEntityOfPage: url,
        ...(looksTurkish(song.content) ? { inLanguage: "tr" } : {}),
        ...(song.originalKey ? { musicalKey: song.originalKey } : {}),
        isAccessibleForFree: true,
        recordedAs: { "@type": "MusicRecording", name: song.songName, byArtist: artist },
      },
      breadcrumbJsonLd(base, songCrumbs(song)),
    ],
  };
}

// ---------- Sanatçı sayfası ----------

export function artistTitle(artist: ArtistGroup): string {
  const n = artist.songs.length;
  return fitTitle([`${artist.name} Akorları – ${n} Şarkı`, `${artist.name} Akorları`]);
}

export function artistDescription(artist: ArtistGroup): string {
  const n = artist.songs.length;
  const lead = `${artist.name} gitar akorları: ${n} şarkı, orijinal ton bilgisiyle.`;
  const tail = "Transpoze ve kapo ile çal.";
  const names = artist.songs.slice(0, 4).map((s) => s.songName);
  const list = [...names];
  while (list.length) {
    const more = list.length < n ? " ve daha fazlası" : "";
    const d = `${lead} ${list.join(", ")}${more}. ${tail}`;
    if (d.length <= DESC_MAX) return d;
    list.pop();
  }
  const d = `${lead} ${tail}`;
  return d.length <= DESC_MAX ? d : lead;
}

export function artistCrumbs(artist: ArtistGroup): Crumb[] {
  return [{ name: "Ana sayfa", path: "/" }, { name: "Sanatçılar", path: "/sanatcilar/" }, { name: `${artist.name} akorları` }];
}

export function artistJsonLd(artist: ArtistGroup, base: string) {
  const url = base + artistPath(artist.slug);
  return {
    "@context": "https://schema.org",
    "@graph": [
      { "@type": "MusicGroup", "@id": `${url}#artist`, name: artist.name, url, mainEntityOfPage: url },
      {
        "@type": "ItemList",
        name: `${artist.name} akorları`,
        numberOfItems: artist.songs.length,
        itemListOrder: "https://schema.org/ItemListOrderAscending",
        itemListElement: artist.songs.map((s, i) => ({
          "@type": "ListItem",
          position: i + 1,
          name: `${s.songName} akorları`,
          url: base + songPath(s),
        })),
      },
      breadcrumbJsonLd(base, artistCrumbs(artist)),
    ],
  };
}

// ---------- Ana sayfa ----------

export function homeJsonLd(base: string) {
  const org = `${base}/#organization`;
  return {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "WebSite",
        "@id": `${base}/#website`,
        name: SITE_NAME,
        url: `${base}/`,
        inLanguage: "tr",
        publisher: { "@id": org },
        potentialAction: {
          "@type": "SearchAction",
          target: { "@type": "EntryPoint", urlTemplate: `${base}/ara/?q={search_term_string}` },
          "query-input": "required name=search_term_string",
        },
      },
      {
        "@type": "Organization",
        "@id": org,
        name: SITE_NAME,
        url: `${base}/`,
        logo: `${base}/favicon.svg`,
        email: "iletisim@gituar.com",
      },
      {
        "@type": "SoftwareApplication",
        name: SITE_NAME,
        operatingSystem: "iOS",
        applicationCategory: "MusicApplication",
        url: APP_STORE_URL,
        installUrl: APP_STORE_URL,
        identifier: APP_STORE_ID,
        offers: { "@type": "Offer", price: "0", priceCurrency: "TRY" },
        publisher: { "@id": org },
      },
    ],
  };
}

// ---------- Sanatçılar dizini ----------

export function artistsIndexJsonLd(base: string, artistCount: number) {
  return {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "CollectionPage",
        name: "Sanatçılar – Gitar Akorları A'dan Z'ye",
        url: `${base}/sanatcilar/`,
        inLanguage: "tr",
        isPartOf: { "@id": `${base}/#website` },
        description: `${artistCount} sanatçının gitar akorları, alfabetik dizin.`,
      },
      breadcrumbJsonLd(base, [{ name: "Ana sayfa", path: "/" }, { name: "Sanatçılar" }]),
    ],
  };
}

/** `</script>` kaçışı: JSON içindeki `<` HTML'e sızmasın. */
export function jsonLdText(data: unknown): string {
  return JSON.stringify(data).replace(/</g, "\\u003c");
}
