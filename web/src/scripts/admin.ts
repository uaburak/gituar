// Yönetim: onay bekleyen kullanıcı şarkıları ve şikayetler (yalnızca users/{uid}.isAdmin; kurallar sunucuda da zorlar).
import type { User } from "firebase/auth";
import { firebaseReady, currentUser, listReports, setReportStatus } from "../lib/firebase-client.ts";
import { apiIsAdmin, listPending, setSongStatus, deleteSong } from "../lib/api-admin.ts";
import { esc, songsByIds } from "../lib/search-client.ts";

const $ = (id: string) => document.getElementById(id)!;
const status = $("admin-status");
const fmt = (d?: Date) => (d ? d.toLocaleDateString("tr-TR", { day: "numeric", month: "short", year: "numeric" }) : "");
let reportFilter: "open" | "closed" = "open";
let me: User;

async function loadPending() {
  const list = $("pending-list");
  const items = (await listPending(me)).map((c) => ({ ...c, songName: c.title, createdAt: new Date(c.createdAt) }));
  $("pending-count").textContent = items.length ? `${items.length} şarkı` : "Bekleyen yok";
  list.innerHTML = items.length
    ? items.map((c) => `<div class="row admin-row" data-id="${esc(c.id)}">
        <div class="row-body">
          <span class="row-title">${esc(c.songName)} <span class="muted">· ${esc(c.artist)}</span></span>
          <span class="row-sub">${esc(c.originalKey || "–")}${c.addedBy ? ` · @${esc(c.addedBy)}` : ""}${c.createdAt ? ` · ${fmt(c.createdAt)}` : ""}</span>
          <details class="admin-details"><summary>İçeriği göster</summary><pre class="chords admin-pre">${esc(c.content)}</pre></details>
        </div>
        <div class="admin-actions">
          <button class="btn btn-primary btn-mini" data-act="approved" type="button">Onayla</button>
          <button class="btn btn-mini btn-danger" data-act="rejected" type="button">Reddet</button>
        </div>
      </div>`).join("")
    : `<div class="row muted small">Onay bekleyen şarkı yok.</div>`;
  list.querySelectorAll<HTMLButtonElement>("[data-act]").forEach((b) =>
    b.addEventListener("click", async () => {
      const row = b.closest<HTMLElement>(".admin-row")!;
      row.querySelectorAll("button").forEach((x) => (x.disabled = true));
      try {
        await setSongStatus(me, row.dataset.id!, b.dataset.act as "approved" | "rejected");
        row.remove();
        const left = list.querySelectorAll(".admin-row").length;
        $("pending-count").textContent = left ? `${left} şarkı` : "Bekleyen yok";
        if (!left) list.innerHTML = `<div class="row muted small">Onay bekleyen şarkı yok.</div>`;
      } catch (e) {
        row.querySelectorAll("button").forEach((x) => (x.disabled = false));
        alert("Kaydedilemedi: " + ((e as Error).message ?? e));
      }
    }),
  );
}

async function loadReports() {
  const list = $("reports-list");
  list.innerHTML = `<div class="row muted small">Yükleniyor…</div>`;
  const items = await listReports(reportFilter === "open" ? ["pending", "in_progress"] : ["reviewed", "dismissed"]);
  const ids = [...new Set(items.map((r) => r.songId).filter(Boolean))];
  const found = await songsByIds(ids).catch(() => []);
  const pathById = new Map(found.map((e) => [e.i, e.p]));
  const label: Record<string, string> = { pending: "Bekliyor", in_progress: "İnceleniyor", reviewed: "Kaldırıldı", dismissed: "Yoksayıldı" };
  list.innerHTML = items.length
    ? items.map((r) => `<div class="row admin-row" data-id="${esc(r.id)}">
        <div class="row-body">
          <span class="row-title">${esc(r.songName)}${r.songArtist ? ` <span class="muted">· ${esc(r.songArtist)}</span>` : ""}</span>
          <span class="row-sub"><strong>${esc(r.reason)}</strong>${r.ownerUsername ? ` · şarkı: @${esc(r.ownerUsername)}` : ""}${r.reportedAt ? ` · ${fmt(r.reportedAt)}` : ""} · ${label[r.status] ?? esc(r.status)}</span>
          ${pathById.get(r.songId) ? `<a class="small" href="${esc(pathById.get(r.songId)!)}" target="_blank" rel="noopener">Şarkıyı aç ›</a>` : ""}
        </div>
        <div class="admin-actions">
          ${r.status === "pending" ? `<button class="btn btn-mini" data-act="in_progress" type="button">İncelemeye al</button>` : ""}
          ${reportFilter === "open" ? `<button class="btn btn-mini btn-danger" data-act="remove" type="button">İçeriği kaldır</button><button class="btn btn-mini" data-act="dismissed" type="button">Yoksay</button>` : (r.status === "dismissed" ? `<button class="btn btn-mini" data-act="in_progress" type="button">Yeniden aç</button>` : "")}
        </div>
      </div>`).join("")
    : `<div class="row muted small">${reportFilter === "open" ? "Açık şikayet yok." : "Kapatılan şikayet yok."}</div>`;
  list.querySelectorAll<HTMLButtonElement>("[data-act]").forEach((b) =>
    b.addEventListener("click", async () => {
      const row = b.closest<HTMLElement>(".admin-row")!;
      const report = items.find((r) => r.id === row.dataset.id)!;
      if (b.dataset.act === "remove" && !confirm(`"${report.songName}" herkes için kaldırılsın mı? Bu işlem geri alınamaz.`)) return;
      row.querySelectorAll("button").forEach((x) => (x.disabled = true));
      try {
        if (b.dataset.act === "remove") {
          await deleteSong(me, report.songId).catch((e: Error) => { if (!/bulunamadı/i.test(e.message)) throw e; });
          await setReportStatus(report.id, "reviewed");
        } else {
          await setReportStatus(row.dataset.id!, b.dataset.act as "in_progress" | "reviewed" | "dismissed");
        }
        await loadReports();
      } catch (e) {
        row.querySelectorAll("button").forEach((x) => (x.disabled = false));
        alert("Kaydedilemedi: " + ((e as Error).message ?? e));
      }
    }),
  );
}

(async () => {
  if (!firebaseReady) { status.textContent = "Web girişi yapılandırılmamış."; return; }
  const user = await currentUser();
  if (!user) { $("admin-auth").hidden = false; status.textContent = ""; return; }
  me = user;
  if (!(await apiIsAdmin(user))) { $("admin-denied").hidden = false; status.textContent = ""; return; }
  $("admin-pending").hidden = false;
  $("admin-reports").hidden = false;
  $("admin-refresh").hidden = false;
  status.textContent = "";
  $("report-filter").querySelectorAll<HTMLButtonElement>("[data-f]").forEach((b) =>
    b.addEventListener("click", () => {
      reportFilter = b.dataset.f as "open" | "closed";
      $("report-filter").querySelectorAll(".chip").forEach((c) => c.classList.toggle("active", c === b));
      loadReports();
    }),
  );
  const refresh = () => Promise.all([loadPending(), loadReports()]).catch((e) => { status.textContent = "Yüklenemedi: " + ((e as Error).message ?? e); });
  $("admin-refresh").addEventListener("click", refresh);
  await refresh();
})();
