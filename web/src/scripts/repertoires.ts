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
        const sub = `${r.songIds.length} şarkı${r.isPublic ? " · herkese açık" : ""}`;
        return `<li><a class="row" href="/repertuar/?id=${esc(r.id)}"><span class="rp-badge rp-badge-list" aria-hidden="true">R</span><span class="rp-text"><span class="row-title">${esc(r.name)}</span><span class="row-note"> · ${sub}</span></span></a></li>`;
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
