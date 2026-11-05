import { firebaseReady, getRepertoire, currentUser } from "../lib/firebase-client.ts";
import { loadIndex, rowHtml } from "../lib/search-client.ts";

const status = document.getElementById("rep-status")!;
(async () => {
  const id = new URL(location.href).searchParams.get("id");
  if (!id) { status.textContent = "Repertuar bulunamadı."; return; }
  if (!firebaseReady) { status.textContent = "Web girişi henüz açık değil."; return; }
  const user = await currentUser();
  const [rep, index] = await Promise.all([getRepertoire(id, user?.uid), loadIndex()]);
  if (!rep) { status.textContent = "Repertuar bulunamadı ya da gizli."; return; }
  document.getElementById("rep-title")!.textContent = rep.name;
  document.title = `${rep.name} · Gituar`;
  const byId = new Map(index.map((e) => [e.i, e]));
  const entries = rep.songIds.map((sid) => byId.get(sid)).filter((e): e is NonNullable<typeof e> => Boolean(e));
  document.getElementById("rep-meta")!.textContent = `${entries.length} şarkı${rep.isPublic ? " · herkese açık" : ""}`;
  document.getElementById("rep-songs")!.innerHTML = entries.map(rowHtml).join("");
  status.textContent = entries.length ? "" : "Bu repertuarda henüz şarkı yok.";
})();
