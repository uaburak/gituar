// Şarkı/sanatçı adresleri ve sanatçıya göre gruplama. Sunucuda (Cloudflare Worker) çalışır; Node modülü kullanmaz.
// "@shared/catalog" içe aktarımları astro.config.mjs'teki takma adla buraya yönlenir.
import type { CatalogSong } from "@shared/types";
import { compareTurkish } from "@shared/turkish";

export function songPath(song: Pick<CatalogSong, "artistSlug" | "slug">): string {
  return `/akor/${song.artistSlug}/${song.slug}/`;
}

export function artistPath(artistSlug: string): string {
  return `/sanatci/${artistSlug}/`;
}

export interface ArtistGroup {
  name: string;
  slug: string;
  songs: CatalogSong[];
}

export function groupByArtist(songs: readonly CatalogSong[]): ArtistGroup[] {
  const map = new Map<string, ArtistGroup>();
  for (const s of songs) {
    let g = map.get(s.artistSlug);
    if (!g) {
      g = { name: s.artist.trim(), slug: s.artistSlug, songs: [] };
      map.set(s.artistSlug, g);
    }
    g.songs.push(s);
  }
  const groups = [...map.values()];
  for (const g of groups) g.songs.sort((a, b) => compareTurkish(a.songName, b.songName));
  groups.sort((a, b) => compareTurkish(a.name, b.name));
  return groups;
}
