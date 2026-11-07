-- Sürüm ve fark sorguları (/v1/version, /v1/changes) bütün tabloyu taramasın diye.
CREATE INDEX IF NOT EXISTS songs_updated ON songs (updated_at);
CREATE INDEX IF NOT EXISTS songs_status_updated ON songs (status, updated_at);
