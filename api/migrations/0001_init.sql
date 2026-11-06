-- Gituar veritabanı (Cloudflare D1). Bütün şarkılar tek tabloda; katalog/kullanıcı şarkısı ayrımı yok.
-- Silinen şarkının satırı silinir (iz kalmaz).

CREATE TABLE IF NOT EXISTS songs (
  id            TEXT PRIMARY KEY,              -- eski katalog numaraları ("1"…) ve kullanıcı şarkıları ("u…") korunur
  artist        TEXT NOT NULL,
  artist_slug   TEXT NOT NULL,
  title         TEXT NOT NULL,
  slug          TEXT NOT NULL,
  original_key  TEXT NOT NULL DEFAULT '',
  content       TEXT NOT NULL DEFAULT '',
  status        TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('draft', 'pending', 'approved', 'rejected')),
  owner_id      TEXT,                          -- Firebase uid (ekleyen)
  added_by      TEXT,                          -- görünen kullanıcı adı
  created_at    INTEGER NOT NULL,              -- ms
  updated_at    INTEGER NOT NULL,              -- ms
  search        TEXT NOT NULL DEFAULT '',      -- Türkçe sadeleştirilmiş "sanatçı şarkı"
  score         INTEGER NOT NULL DEFAULT 0,    -- tüm zamanlar popülerlik puanı (song_actions toplamı)
  UNIQUE (artist_slug, slug)
);
CREATE INDEX IF NOT EXISTS songs_status_created ON songs (status, created_at DESC);
CREATE INDEX IF NOT EXISTS songs_status_score ON songs (status, score DESC);
CREATE INDEX IF NOT EXISTS songs_status_artist ON songs (status, artist_slug, title);
CREATE INDEX IF NOT EXISTS songs_owner ON songs (owner_id);

-- Arama: üçlü harf dizini, kelimenin bir parçasıyla da bulur ("gulum" → "Gülümse")
CREATE VIRTUAL TABLE IF NOT EXISTS songs_fts USING fts5 (search, content = 'songs', content_rowid = 'rowid', tokenize = 'trigram');
CREATE TRIGGER IF NOT EXISTS songs_ai AFTER INSERT ON songs BEGIN
  INSERT INTO songs_fts (rowid, search) VALUES (new.rowid, new.search);
END;
CREATE TRIGGER IF NOT EXISTS songs_ad AFTER DELETE ON songs BEGIN
  INSERT INTO songs_fts (songs_fts, rowid, search) VALUES ('delete', old.rowid, old.search);
END;
CREATE TRIGGER IF NOT EXISTS songs_au AFTER UPDATE OF search ON songs BEGIN
  INSERT INTO songs_fts (songs_fts, rowid, search) VALUES ('delete', old.rowid, old.search);
  INSERT INTO songs_fts (rowid, search) VALUES (new.rowid, new.search);
END;

-- Yöneticiler (Firebase uid)
CREATE TABLE IF NOT EXISTS admins (
  uid TEXT PRIMARY KEY
);

-- Popülerlik: kişi × şarkı × işlem başına tek kayıt. Kişi kimliği özetlenmiş (hash) tutulur.
-- view = 1, favorite = 4, repertoire = 5 puan. Favori/repertuardan çıkarınca kayıt silinir, puan geri alınır.
CREATE TABLE IF NOT EXISTS song_actions (
  song_id    TEXT NOT NULL,
  actor      TEXT NOT NULL,
  action     TEXT NOT NULL CHECK (action IN ('view', 'favorite', 'repertoire')),
  created_at INTEGER NOT NULL,
  PRIMARY KEY (song_id, actor, action)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS song_actions_recent ON song_actions (created_at);
