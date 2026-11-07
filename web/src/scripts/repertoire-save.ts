// Herkese açık repertuar sayfası: "Repertuara kaydet" — iOS'taki gibi kullanıcının kendi listelerine kopyalar.
const head = document.getElementById("rep");
const btn = document.getElementById("rep-save") as HTMLButtonElement | null;

function setSaved() {
  if (!btn) return;
  btn.disabled = true;
  btn.classList.add("is-saved");
  btn.title = "Kaydedildi";
  btn.setAttribute("aria-label", "Kaydedildi");
  const svg = btn.querySelector("svg");
  if (svg) svg.setAttribute("fill", "currentColor"); // kayıtlı: yer imi dolu
}

if (head && btn) {
  const { id, name = "", owner = "", songs = "" } = head.dataset;
  const songIds = songs.split(",").filter(Boolean);
  // Giriş durumu yalnızca gerektiğinde: kayıtlı mı, sahibi mi?
  void (async () => {
    if (!document.documentElement.classList.contains("signed-in")) return;
    const { currentUser, isRepertoireCopied } = await import("../lib/firebase-client.ts");
    const user = await currentUser();
    if (!user) return;
    if (user.uid === owner) { btn.hidden = true; return; }
    if (id && (await isRepertoireCopied(user.uid, id))) setSaved();
  })();
  btn.addEventListener("click", async () => {
    if (!id || btn.disabled) return;
    const { currentUser, copyRepertoire } = await import("../lib/firebase-client.ts");
    const user = await currentUser();
    if (!user) { location.href = `/giris/?next=${encodeURIComponent(location.pathname)}`; return; }
    btn.disabled = true;
    try {
      await copyRepertoire(user.uid, { id, name, songIds });
      setSaved();
    } catch {
      btn.disabled = false;
      btn.title = "Kaydedilemedi, tekrar dene";
    }
  });
}
