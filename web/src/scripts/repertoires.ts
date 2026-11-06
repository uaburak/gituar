import { firebaseReady, currentUser, listMyRepertoires, createRepertoire } from "../lib/firebase-client.ts";
import { esc } from "../lib/search-client.ts";

const status = document.getElementById("rep-status")!;
const meta = document.getElementById("rep-meta")!;
const grid = document.getElementById("rep-grid")!;
const form = document.getElementById("rep-create") as HTMLFormElement;
const newBtn = document.getElementById("rep-new-btn") as HTMLButtonElement;

(async () => {
  if (!firebaseReady) { status.textContent = "Web girişi henüz açık değil; repertuarlar şimdilik iPhone uygulamasında."; return; }
  const user = await currentUser();
  if (!user) { document.getElementById("rep-auth")!.hidden = false; status.textContent = ""; return; }
  form.hidden = false;
  newBtn.hidden = false;
  newBtn.addEventListener("click", () => form.querySelector<HTMLInputElement>("input")?.focus());

  async function load() {
    const reps = await listMyRepertoires(user!.uid);
    grid.innerHTML = reps
      .map((r) => {
        const initial = esc(r.name.trim().charAt(0).toLocaleUpperCase("tr-TR") || "?");
        const sub = `${r.songIds.length} şarkı${r.isPublic ? " · herkese açık" : ""}`;
        return `<a class="card pick" href="/repertuar/?id=${esc(r.id)}"><span class="pick-tile" aria-hidden="true">${initial}</span><span class="pick-body"><span class="pick-title">${esc(r.name)}</span><span class="muted small">${sub}</span></span><span class="pick-arrow" aria-hidden="true">›</span></a>`;
      })
      .join("");
    meta.textContent = `${reps.length} repertuar · iPhone'daki Gituar ile eşitlenir`;
    status.textContent = reps.length ? "" : "Henüz repertuar yok. Yukarıdan bir tane oluştur.";
  }
  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    const name = (new FormData(form).get("name") as string).trim();
    if (!name) return;
    await createRepertoire(user.uid, name);
    form.reset();
    await load();
  });
  await load();
})();
