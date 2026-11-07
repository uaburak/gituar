-- Ritim / arpej / tempo / tartım: tek JSON sütunu {"pattern","arpeggio","tempo","meter"} (hepsi isteğe bağlı).
-- ÖNEMLİ: API'nin bu sütunu okuyan sürümü yayına alınmadan ÖNCE uygulanmalı; yoksa şarkı sorguları hata verir.
ALTER TABLE songs ADD COLUMN rhythm TEXT;
