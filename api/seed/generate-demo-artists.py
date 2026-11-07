# Test verisi: 20 hayalî sanatçı, her birine rastgele sayıda (2–24) özgün şarkı.
# Adlar, şarkı adları ve sözler bu betikte üretildi; gerçek bir sanatçı ya da eserden alınmadı.
# Kimlikler "dm" ile başlar; silmek için: DELETE FROM songs WHERE id LIKE 'dm%';
# Çıktı: seed/demo-artists.sql — D1'e tek seferde uygulanır.
import random, time, unicodedata, re, json, pathlib

random.seed(2026_11_07)
OWNER = "2VXat5X3TuZxiY232u14UIE2bwo2"

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


ARTISTS = [
    "Deniz Aksoy", "Mavi Rota", "Selin Karaca", "Kuzey Yolcuları", "Ece Yaman", "Taşplak", "Arda Demirhan",
    "Gece Treni Grubu", "Zeynep Sarp", "Ozan Tunalı", "Liman Sokak", "Nehir Akın", "Karakış", "Ilgaz Ekin",
    "Duru Atlas", "Bulut Kaptan", "Mert Ayaz", "Sarmaşık", "Elif Gündoğdu", "Yolcu Kuşlar",
]
KEYS = ["G", "Am", "C", "Em", "D", "Dm", "A", "Bm", "E", "F#m", "F", "Cm", "Bb", "Gm", "Eb", "C#m", "Ab", "B"]
W1 = ["Sabah", "Gece", "Eski", "Mavi", "Kırık", "Son", "Uzak", "Sessiz", "Yalnız", "Sarı", "Kara", "Beyaz", "Ilık", "Yarım", "Derin", "Küçük", "Sonsuz", "İlk"]
W2 = ["Liman", "Sokak", "Vapur", "Mektup", "Bahçe", "Pencere", "Yol", "Şehir", "Rüzgâr", "Deniz", "Saat", "Köprü", "Kapı", "Sahil", "Tren", "Yıldız", "Masal", "Şarkı", "Bulut", "Gölge"]
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
seq = 0
for a_i, artist in enumerate(ARTISTS):
    count = random.randint(2, 24)
    titles = set()
    while len(titles) < count:
        titles.add(f"{random.choice(W1)} {random.choice(W2)}")
    for t_i, title in enumerate(sorted(titles)):
        seq += 1
        key = random.choice(KEYS)
        prog = random.choice(MINOR if key.endswith("m") else MAJOR)
        chords = [chord(key, s, q) for s, q in prog]
        v = random.sample(VERSE, 4)
        c1, c2 = random.choice(CHORUS)
        parts = ["Giriş", "  ".join(chords + chords), ""]
        for i, lyr in enumerate(v):
            parts.append(line_pair(chords[i % 2 * 2:i % 2 * 2 + 2], lyr))
        parts += ["", "Nakarat", line_pair(chords[:2], c1), line_pair(chords[2:], c2), ""]
        v2 = random.sample([x for x in VERSE if x not in v], 2)
        for i, lyr in enumerate(v2):
            parts.append(line_pair(chords[i * 2:i * 2 + 2], lyr))
        parts += ["", "Nakarat (2x)", "", "Bitiş", "  ".join(chords) + "  " + chords[0]]
        # Sanatçılar farklı günlerde eklenmiş gibi: listenin sonundaki en yeni
        created = now - (len(ARTISTS) - a_i) * 86_400_000 + t_i * 60_000
        songs.append(dict(id=f"dm{seq:03d}", artist=artist, artist_slug=slugify(artist), title=title, slug=slugify(title), key=key,
                          content="\n".join(parts), created=created, search=norm(f"{artist} {title}"), score=random.randint(0, 40)))

def q(s): return "'" + s.replace("'", "''") + "'"
sql = []
for s in songs:
    sql.append("INSERT INTO songs (id, artist, artist_slug, title, slug, original_key, content, status, owner_id, added_by, created_at, updated_at, search, score) VALUES ("
               + ", ".join([q(s["id"]), q(s["artist"]), q(s["artist_slug"]), q(s["title"]), q(s["slug"]), q(s["key"]), q(s["content"]),
                            "'approved'", q(OWNER), q("Burak KOÇ"), str(s["created"]), str(s["created"]), q(s["search"]), str(s["score"])]) + ");")
pathlib.Path(__file__).with_name("demo-artists.sql").write_text("\n".join(sql) + "\n")
from collections import Counter
c = Counter(s["artist"] for s in songs)
print(len(songs), "şarkı,", len(c), "sanatçı")
for a, n in c.items(): print(f"  {a}: {n}")
