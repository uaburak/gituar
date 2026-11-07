// Ana sayfa "Repertuarlarım": açılınca giriş yapmış kullanıcının repertuarlarını listeler (Firebase yalnızca açılınca yüklenir).
import { esc } from "../lib/search-client.ts";

const section = document.getElementById("my-reps") as HTMLDetailsElement | null;
const list = document.getElementById("my-reps-list");
const status = document.getElementById("my-reps-status");
let started = false;

async function load() {
  if (!list || !status || started) return;
  started = true;
  try {
    const { firebaseReady, currentUser, listMyRepertoires } = await import("../lib/firebase-client.ts");
    if (!firebaseReady) { status.textContent = "Web girişi henüz açık değil; repertuarlar şimdilik iPhone uygulamasında."; return; }
    const user = await currentUser();
    if (!user) { status.innerHTML = 'Repertuarlarını görmek için <a href="/giris/?next=/">giriş yap</a>.'; return; }
    const reps = await listMyRepertoires(user.uid);
    list.innerHTML = reps
      .map((r) => `<li><a class="row" href="/repertuar/?id=${esc(r.id)}" title="${esc(r.name)}"><span class="rp-badge rp-badge-list" aria-hidden="true">R</span><span class="rp-text"><span class="row-title">${esc(r.name)}</span><span class="row-note"> · ${r.songIds.length} şarkı</span></span></a></li>`)
      .join("");
    status.hidden = reps.length > 0;
    status.textContent = "Henüz repertuarın yok. Şarkı sayfasındaki \"Repertuara Ekle\" ile oluşturabilirsin.";
  } catch {
    status.textContent = "Repertuarlar yüklenemedi, birazdan yeniden dene.";
    started = false;
  }
}
section?.addEventListener("toggle", () => { if (section.open) load(); });
