/** Katalogdaki bir resmi şarkı. Firestore `songs/{id}` dokümanı ve snapshot kaydı aynı alanları taşır. */
export interface CatalogSong {
  /** Eski docId ile aynı (sayısal metin). Repertuarlardaki songIds bu değere bağlıdır. */
  id: string;
  artist: string;
  songName: string;
  originalKey: string;
  content: string;
  /** URL parçaları: /akor/{artistSlug}/{slug}/ */
  artistSlug: string;
  slug: string;
  /** Tekil artan değişiklik sayacı; fark senkronu `seq > lastSeq` ile çalışır. */
  seq: number;
  createdAt?: string;
  addedBy?: string;
  /** Silinen şarkı farkı taşısın diye doküman kalır, bu alan true olur. */
  deleted?: boolean;
}

/** `shared/catalog/catalog.deflate` içindeki JSON. */
export interface CatalogSnapshot {
  seq: number;
  count: number;
  publishedAt: string;
  songs: CatalogSong[];
}

/** Firestore `catalog/meta` dokümanı. */
export interface CatalogMeta {
  seq: number;
  count: number;
  publishedAt: string;
}

/** Tarayıcı aramasının indirdiği küçük indeks kaydı. */
export interface SearchIndexEntry {
  i: string; // id
  a: string; // artist
  s: string; // songName
  k: string; // originalKey
  p: string; // path (/akor/...)
}
