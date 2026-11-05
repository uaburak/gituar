import { firebaseReady, currentUser, listMyRepertoires, createRepertoire } from "../lib/firebase-client.ts";
import { loadIndex, esc } from "../lib/search-client.ts";

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
    const [reps, index] = await Promise.all([listMyRepertoires(user!.uid), loadIndex()]);
    const byId = new Map(index.map((e) => [e.i, e]));
    grid.querySelectorAll(".rep-card:not(form)").forEach((el) => el.remove());
    const cards = reps.map((r) => {
      const names = r.songIds.map((id) => byId.get(id)).filter(Boolean).slice(0, 3)
        .map((e) => `<span>${esc(e!.s)} · ${esc(e!.a)}</span>`).join("");
      const more = r.songIds.length > 3 ? `<span class="rep-more">+${r.songIds.length - 3} şarkı</span>` : "";
      return `<a class="card rep-card" href="/repertuar/?id=${esc(r.id)}"><h3>${esc(r.name)}</h3><span class="muted small">${r.songIds.length} şarkı${r.isPublic ? " · herkese açık" : ""}</span>${names || more ? `<div class="rep-songs">${names}${more}</div>` : ""}</a>`;
    });
    form.insertAdjacentHTML("beforebegin", cards.join(""));
    meta.textContent = `${reps.length} repertuar · iPhone'daki Gituar ile eşitlenir`;
    status.textContent = reps.length ? "" : "Henüz repertuar yok. Sağdaki kartla bir tane oluştur.";
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
