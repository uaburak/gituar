# Test verisi: "Burak KOÇ" adına 50 özgün şarkı (sözler bu betikte yazıldı, başka bir eserden alınmadı).
# Çıktı: seed/burak-koc.sql — D1'e tek seferde uygulanır.
import random, time, unicodedata, re, json, pathlib

random.seed(2026_11_06)
OWNER = "2VXat5X3TuZxiY232u14UIE2bwo2"
ARTIST = "Burak KOÇ"

FOLD = str.maketrans({"ç": "c", "Ç": "c", "ğ": "g", "Ğ": "g", "ı": "i", "İ": "i", "ö": "o", "Ö": "o", "ş": "s", "Ş": "s", "ü": "u", "Ü": "u"})
def norm(s):
    s = s.translate(FOLD).lower()
    return unicodedata.normalize("NFD", s).encode("ascii", "ignore").decode()
def slugify(s):
    s = norm(s)
    s = re.sub(r"[''\"’?!,;.:_+()\[\]&/\\]", " ", s)
    s = re.sub(r"[^a-z0-9 -]+", "", s).strip()
    s = re.sub(r"\s+", "-", s)
    return re.sub(r"-+", "-", s).strip("-") or "x"

SHARP = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
FLAT = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
def chord(key, degree_semi, quality):
    minor = key.endswith("m")
    root = key[:-1] if minor else key
    idx = SHARP.index(root) if root in SHARP else FLAT.index(root)
    names = FLAT if ("b" in root or root == "F") else SHARP
    return names[(idx + degree_semi) % 12] + quality

# Akor dizileri (yarım ses, nitelik): majör ve minör tonlar için
MAJOR = [
    [(0, ""), (7, ""), (9, "m"), (5, "")],      # I V vi IV
    [(9, "m"), (5, ""), (0, ""), (7, "")],      # vi IV I V
    [(0, ""), (5, ""), (7, ""), (5, "")],       # I IV V IV
    [(0, ""), (9, "m"), (2, "m"), (7, "7")],    # I vi ii V7
    [(0, ""), (4, "m"), (5, ""), (7, "")],      # I iii IV V
]
MINOR = [
    [(0, "m"), (8, ""), (3, ""), (10, "")],     # i VI III VII
    [(0, "m"), (5, "m"), (7, "7"), (0, "m")],   # i iv V7 i
    [(0, "m"), (10, ""), (8, ""), (7, "")],     # i VII VI V
    [(0, "m"), (3, ""), (10, ""), (5, "m")],    # i III VII iv
    [(0, "m"), (5, "m"), (8, ""), (7, "7")],    # i iv VI V7
]

TITLES = [
    ("Sabah Treni", "G"), ("Kıyıda Bekleyen", "Am"), ("Mavi Kapı", "C"), ("Eski Sokak", "Em"), ("Yağmur Sonrası", "D"),
    ("Pencere Önü", "Dm"), ("Uzak Değil", "A"), ("Gece Yarısı Mektubu", "Bm"), ("Fener", "E"), ("Son Vapur", "F#m"),
    ("İzmir Akşamı", "F"), ("Kırık Saat", "Cm"), ("Bir Gün Daha", "Bb"), ("Rüzgârın Yönü", "Gm"), ("Taş Merdiven", "Eb"),
    ("Sessiz Liman", "C#m"), ("Kum Saati", "G"), ("Kara Tren", "Am"), ("Çınar Altı", "D"), ("Unutulmuş Şarkı", "Em"),
    ("Ay Işığı", "C"), ("Yolun Sonu", "Dm"), ("Sarı Yaprak", "A"), ("Gölgeler", "Bm"), ("Deniz Feneri", "E"),
    ("Kapalı Çarşı", "F#m"), ("Eylül", "F"), ("Bekle Beni", "Cm"), ("Yaz Gecesi", "B"), ("Dönüş", "Gm"),
    ("Kar Yağarken", "G"), ("Avuçlarımda", "Am"), ("Göç", "D"), ("Kalbimdeki Şehir", "Em"), ("Sokak Lambası", "C"),
    ("Hasret", "Dm"), ("Kuşluk Vakti", "A"), ("Son Mektup", "Bm"), ("Kırmızı Bisiklet", "E"), ("Duman", "F#m"),
    ("Ayrılık Durağı", "Ab"), ("Ilık Rüzgâr", "Cm"), ("Yarım Kalan", "G"), ("Tren Yolu", "Am"), ("Köprüaltı", "D"),
    ("Uykusuz", "Em"), ("Bahar Gelince", "C"), ("Gurbet", "Dm"), ("Sonbahar Valsi", "F"), ("Eve Dönüş", "A"),
]

VERSE = [
    "Sabah oldu, şehir yine uyanmadı", "Bir bavul, bir şarkı, bir de sen", "Pencereden düşen ışık seni anlatır",
    "Adını yazdım buğulu camlara", "Yollar uzar, gece kısalır", "Eski bir plak döner odada",
    "Kaldırımlar ıslak, adımlar yavaş", "Bir sigara yanar, sönmez içimde", "Martılar bilir, deniz bilir",
    "Saat durdu, zaman bizden yana değil", "Bir mektup yazdım, gönderemedim", "Sokak lambası titrer gibi",
    "Ceplerimde kum, avucumda rüzgâr", "Kapı aralık, umut içeride", "Bir tren kalkar, biri kalır geride",
    "Gölgeler uzar duvarlarda", "Yağmur başladı, şemsiye yok", "Çınarın altında bir bank, bir anı",
    "Sesin geliyor uzak bir radyodan", "Her köşe başında bir eski sen", "Fener yanar, gemi yok",
    "Bavulumu topladım, gitmedim", "Kalbim bir şehir, sokakları sen", "Ay yine dolu, ben yine yarım",
]
CHORUS = [
    ("Gel desen gelirim, kal desen kalırım", "Bir sözüne bakar bu deli yürek"),
    ("Hadi söyle bana, nerdesin şimdi", "Bu şehir sensiz çok kalabalık"),
    ("Dönsen de olur, dönmesen de", "Ben bu şarkıyı her gece söylerim"),
    ("Uzak değil, inan uzak değil", "Bir adım atsan yanındayım"),
    ("Yağmur yağsın, sel olsun", "Senin adın dilimde dua olsun"),
    ("Ah bu yollar, ah bu yollar", "Beni senden alıp götürmesin"),
    ("Bekle beni, bekle beni", "Son vapura yetişirim belki"),
    ("Bir gün daha geçti sensiz", "Saymayı bıraktım çoktan"),
]

def line_pair(chords, lyric):
    # Akorları söz satırının üstüne eşit aralıkla yerleştir
    width = max(len(lyric), 24)
    step = width // len(chords)
    out = ""
    for i, c in enumerate(chords):
        pos = i * step
        out = out.ljust(pos) + c + " "
    return out.rstrip() + "\n" + lyric

songs = []
now = int(time.time() * 1000)
for n, (title, key) in enumerate(TITLES):
    prog = random.choice(MINOR if key.endswith("m") else MAJOR)
    chords = [chord(key, s, q) for s, q in prog]
    v = random.sample(VERSE, 4)
    c1, c2 = random.choice(CHORUS)
    parts = ["Giriş", "  ".join(chords + chords), ""]
    for i, lyr in enumerate(v):
        parts.append(line_pair(chords[i % 2 * 2:i % 2 * 2 + 2], lyr))
    parts += ["", "Nakarat", line_pair(chords[:2], c1), line_pair(chords[2:], c2), line_pair(chords[:2], c1), line_pair(chords[2:], c2.replace("bu", "o")), ""]
    v2 = random.sample([x for x in VERSE if x not in v], 2)
    for i, lyr in enumerate(v2):
        parts.append(line_pair(chords[i * 2:i * 2 + 2], lyr))
    parts += ["", "Nakarat (2x)", "", "Bitiş", "  ".join(chords) + "  " + chords[0]]
    content = "\n".join(parts)
    sid = f"bk{n + 1:03d}"
    created = now - (len(TITLES) - n) * 3600_000  # en son eklenen listenin sonu
    songs.append(dict(id=sid, artist=ARTIST, artist_slug=slugify(ARTIST), title=title, slug=slugify(title), key=key,
                      content=content, created=created, search=norm(f"{ARTIST} {title}")))

def q(s): return "'" + s.replace("'", "''") + "'"
sql = ["INSERT OR IGNORE INTO admins (uid) VALUES ('2VXat5X3TuZxiY232u14UIE2bwo2'), ('OlT50mv7QBcXy4PkdmIPZGf2HC72');"]
for s in songs:
    sql.append("INSERT INTO songs (id, artist, artist_slug, title, slug, original_key, content, status, owner_id, added_by, created_at, updated_at, search) VALUES ("
               + ", ".join([q(s["id"]), q(s["artist"]), q(s["artist_slug"]), q(s["title"]), q(s["slug"]), q(s["key"]), q(s["content"]),
                            "'approved'", q(OWNER), q("Burak KOÇ"), str(s["created"]), str(s["created"]), q(s["search"])]) + ");")
pathlib.Path(__file__).with_name("burak-koc.sql").write_text("\n".join(sql) + "\n")
print(len(songs), "şarkı;", songs[0]["artist_slug"], "|", songs[0]["slug"])
print(songs[3]["content"])
