# Kullanıcının getirdiği JSON'u D1'e yükler (Gituar içe aktarma biçimi: artist, title, key, content, rhythm, arpeggio, tempo, meter).
# - Aynı sanatçı + şarkı (slug'a göre) veritabanında ya da dosyada varsa atlanır.
# - Sanatçı veritabanında varsa onun yazımı kullanılır (ikinci bir sanatçı oluşmaz).
# - Her partinin kimlikleri ortak ön ekle başlar; geri almak için: DELETE FROM songs WHERE id LIKE '<önek>%';
# Kullanım: python3 -I seed/import-json.py <dosya.json> <önek> <mevcut.json>   (mevcut.json: veritabanındaki artist/slug listesi)
import json, sys, time, re, unicodedata, pathlib

FOLD = str.maketrans({"ç": "c", "Ç": "c", "ğ": "g", "Ğ": "g", "ı": "i", "İ": "i", "ö": "o", "Ö": "o", "ş": "s", "Ş": "s", "ü": "u", "Ü": "u"})
def norm(s): return unicodedata.normalize("NFD", s.translate(FOLD).lower()).encode("ascii", "ignore").decode()
def slugify(s):
    s = re.sub(r"[''\"’?!,;.:_+()\[\]&/\\]", " ", norm(s))
    s = re.sub(r"[^a-z0-9 -]+", "", s).strip()
    s = re.sub(r"\s+", "-", s); s = re.sub(r"-+", "-", s).strip("-")
    return s or "x"

OWNER, ADDED_BY = "2VXat5X3TuZxiY232u14UIE2bwo2", "burak"
src, prefix, existing_path = sys.argv[1], sys.argv[2], sys.argv[3]
songs = json.load(open(src, encoding="utf-8"))
existing = json.load(open(existing_path, encoding="utf-8"))
taken = {(e["artist_slug"], e["slug"]) for e in existing}
artist_name = {}
for e in existing: artist_name.setdefault(e["artist_slug"], e["artist"])

rows, skipped, problems = [], [], []
now = int(time.time() * 1000)
for i, s in enumerate(songs):
    artist = re.sub(r"\s+", " ", (s.get("artist") or "")).strip()
    title = re.sub(r"\s+", " ", (s.get("title") or "")).strip()
    content = (s.get("content") or "").replace("\r", "").strip("\n")
    if not artist or not title or not content:
        problems.append(f"{i + 1}. kayıt: sanatçı, şarkı adı ya da içerik eksik"); continue
    a_slug, slug = slugify(artist), slugify(title)
    if (a_slug, slug) in taken:
        skipped.append(f"{artist} - {title}"); continue
    taken.add((a_slug, slug))
    artist = artist_name.setdefault(a_slug, artist)
    key = (s.get("key") or s.get("original_key") or "").strip()
    rhythm = {k: v for k, v in {
        "pattern": (s.get("rhythm") or "").strip() or None,
        "arpeggio": (s.get("arpeggio") or "").strip() or None,
        "tempo": s.get("tempo") or None,
        "meter": (s.get("meter") or "").strip() or None,
    }.items() if v}
    rows.append(dict(id=f"{prefix}{len(rows) + 1:03d}", artist=artist, artist_slug=a_slug, title=title, slug=slug, key=key,
                     content=content, created=now + len(rows), search=norm(f"{artist} {title}"), rhythm=json.dumps(rhythm, ensure_ascii=False) if rhythm else None))

def q(v): return "NULL" if v is None else "'" + str(v).replace("'", "''") + "'"
sql = ["INSERT INTO songs (id, artist, artist_slug, title, slug, original_key, content, status, owner_id, added_by, created_at, updated_at, search, rhythm) VALUES ("
       + ", ".join([q(r["id"]), q(r["artist"]), q(r["artist_slug"]), q(r["title"]), q(r["slug"]), q(r["key"]), q(r["content"]), "'approved'",
                    q(OWNER), q(ADDED_BY), str(r["created"]), str(r["created"]), q(r["search"]), q(r["rhythm"])]) + ");" for r in rows]
out = pathlib.Path(existing_path).with_name(f"{prefix}.sql")
out.write_text("\n".join(sql) + "\n", encoding="utf-8")
print(f"eklenecek: {len(rows)}  atlanan (zaten var): {len(skipped)}  sorunlu: {len(problems)}")
for x in skipped: print("  atla:", x)
for x in problems: print("  sorun:", x)
print("ritimli:", sum(1 for r in rows if r["rhythm"] and "pattern" in r["rhythm"]), " arpejli:", sum(1 for r in rows if r["rhythm"] and "arpeggio" in r["rhythm"]))
print("SQL:", out)
