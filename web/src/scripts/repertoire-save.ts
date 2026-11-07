// Herkese açık repertuar sayfası: "Repertuara kaydet" — iOS'taki gibi kullanıcının kendi listelerine kopyalar.
const head = document.getElementById("rep");
const btn = document.getElementById("rep-save") as HTMLButtonElement | null;
const label = btn?.querySelector("span");

function setSaved() {
  if (!btn || !label) return;
  btn.disabled = true;
  btn.classList.add("is-saved");
  label.textContent = "Kaydedildi";
  const svg = btn.querySelector("svg");
  if (svg) svg.innerHTML = '<circle cx="12" cy="12" r="9"/><path d="m8 12.2 2.8 2.8L16.2 9"/>';
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
      if (label) label.textContent = "Kaydedilemedi, tekrar dene";
    }
  });
}
