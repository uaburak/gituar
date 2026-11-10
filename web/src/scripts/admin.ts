// Yönetim: onay bekleyen kullanıcı şarkıları, şikayetler ve Pro üyeler (yalnızca users/{uid}.isAdmin; kurallar sunucuda da zorlar).
import type { User } from "firebase/auth";
import { firebaseReady, currentUser, listReports, setReportStatus, findUserByUsername, grantPro, revokePro, listProUsers, createPublicRepertoires } from "../lib/firebase-client.ts";
import { apiIsAdmin, listPending, setSongStatus, deleteSong, validImport, importSong, resolveSongRefs, type ImportableSong, type BulkRepertoireEntry } from "../lib/api-admin.ts";
import { getProfile } from "../lib/user-data.ts";
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

async function loadPro() {
  const list = $("pro-list");
  list.innerHTML = `<div class="row muted small">Yükleniyor…</div>`;
  const users = await listProUsers();
  $("pro-count").textContent = users.length ? `${users.filter((u) => u.isPro).length} aktif` : "";
  const until = (d?: Date) => (d ? fmt(d) + "'e kadar" : "süresiz");
  list.innerHTML = users.length
    ? users.map((u) => {
        const parts = [
          u.gift?.active ? `Hediye · ${until(u.gift.until)}${u.gift.note ? ` · ${esc(u.gift.note)}` : ""}` : "",
          u.subscription?.active ? `App Store · ${until(u.subscription.until)}` : "",
        ].filter(Boolean).join(" · ");
        return `<div class="row admin-row" data-uid="${esc(u.uid)}">
          <div class="row-body">
            <span class="row-title">@${esc(u.username || "?")}${u.isPro ? "" : ` <span class="muted">· süresi dolmuş</span>`}</span>
            <span class="row-sub">${parts}</span>
          </div>
          <div class="admin-actions">${u.gift?.active ? `<button class="btn btn-mini btn-danger" data-act="revoke" type="button">Pro'yu geri al</button>` : ""}</div>
        </div>`;
      }).join("")
    : `<div class="row muted small">Pro üye yok.</div>`;
  list.querySelectorAll<HTMLButtonElement>("[data-act=revoke]").forEach((b) =>
    b.addEventListener("click", async () => {
      const row = b.closest<HTMLElement>(".admin-row")!;
      if (!confirm("Bu kullanıcının hediye Pro'su geri alınsın mı?")) return;
      b.disabled = true;
      try { await revokePro(row.dataset.uid!); await loadPro(); }
      catch (e) { b.disabled = false; alert("Kaydedilemedi: " + ((e as Error).message ?? e)); }
    }),
  );
}

function setupProForm() {
  const form = $("pro-form") as HTMLFormElement;
  const msg = $("pro-msg");
  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    const username = ($("pro-username") as HTMLInputElement).value;
    const months = Number(($("pro-duration") as HTMLSelectElement).value);
    const note = ($("pro-note") as HTMLInputElement).value.trim();
    msg.textContent = "Aranıyor…";
    try {
      const u = await findUserByUsername(username);
      if (!u) { msg.textContent = `@${username.replace(/^@/, "")} adında kullanıcı bulunamadı.`; return; }
      let until: Date | null = null;
      if (months > 0) {
        // Mevcut hediye hâlâ sürüyorsa üstüne eklenir
        const base = u.gift?.active && u.gift.until && u.gift.until > new Date() ? new Date(u.gift.until) : new Date();
        base.setMonth(base.getMonth() + months);
        until = base;
      }
      await grantPro(me.uid, u.uid, until, note);
      msg.textContent = `@${u.username} artık Pro (${until ? fmt(until) + "'e kadar" : "süresiz"}). Uygulamada ve sitede reklamlar kapanır.`;
      form.reset();
      await loadPro();
    } catch (err) {
      msg.textContent = "Kaydedilemedi: " + ((err as Error).message ?? err);
    }
  });
}

async function readJson<T>(input: HTMLInputElement): Promise<T> {
  const file = input.files?.[0];
  if (!file) throw new Error("Dosya seçilmedi");
  return JSON.parse(await file.text()) as T;
}

/** JSON'dan şarkı içe aktarma: geçerli olanlar sırayla API'ye gönderilir, ilerleme gösterilir. */
function setupSongImport(username: string) {
  const file = $("imp-file") as HTMLInputElement, start = $("imp-start") as HTMLButtonElement, msg = $("imp-msg"), preview = $("imp-preview");
  let valid: ImportableSong[] = [];
  file.addEventListener("change", async () => {
    start.disabled = true;
    preview.innerHTML = "";
    try {
      const data = await readJson<ImportableSong[]>(file);
      if (!Array.isArray(data) || !data.length) throw new Error("Dosyanın [{\"songName\", \"artist\", \"originalKey\", \"content\"}] biçiminde olduğundan emin ol.");
      valid = data.filter(validImport);
      const skipped = data.length - valid.length;
      msg.textContent = `${valid.length} şarkı yüklenmeye hazır${skipped ? ` · ${skipped} şarkı eksik alan nedeniyle atlanacak` : ""}.`;
      preview.innerHTML = valid.slice(0, 50).map((x) => `<div class="row"><span class="row-body"><span class="row-title">${esc(x.songName!)} <span class="muted">· ${esc(x.artist!)}</span></span><span class="row-sub">${esc(x.originalKey!)}</span></span></div>`).join("")
        + (valid.length > 50 ? `<div class="row muted small">… ve ${valid.length - 50} şarkı daha</div>` : "");
      start.disabled = valid.length === 0;
    } catch (e) {
      msg.textContent = "Geçersiz JSON: " + (e as Error).message;
    }
  });
  start.addEventListener("click", async () => {
    start.disabled = true;
    file.disabled = true;
    let ok = 0, failed = 0, last = "";
    for (const x of valid) {
      try { await importSong(me, x, username); ok++; } catch (e) { failed++; last = (e as Error).message; }
      msg.textContent = `Yükleniyor… ${ok + failed}/${valid.length}`;
    }
    msg.textContent = `${ok} şarkı yayına eklendi${failed ? ` · ${failed} şarkı eklenemedi (${last})` : ""}.`;
    file.disabled = false;
    file.value = "";
    preview.innerHTML = "";
  });
}

/** Toplu repertuar yükleme: şarkı gösterimleri kimliğe çevrilir, bulunamayanlar raporlanır. */
function setupBulkImport(username: string) {
  const file = $("bulk-file") as HTMLInputElement, start = $("bulk-start") as HTMLButtonElement, msg = $("bulk-msg"), preview = $("bulk-preview");
  let entries: BulkRepertoireEntry[] = [];
  let resolved: Map<string, string> = new Map();
  file.addEventListener("change", async () => {
    start.disabled = true;
    preview.innerHTML = "";
    try {
      const data = await readJson<BulkRepertoireEntry[]>(file);
      if (!Array.isArray(data) || !data.length || data.some((e) => typeof e?.name !== "string" || !Array.isArray(e.songIds))) throw new Error("Biçim [{\"name\", \"songIds\": [...]}] olmalı.");
      entries = data.map((e) => ({ name: e.name.trim(), songIds: e.songIds.map(String) })).filter((e) => e.name);
      msg.textContent = "Şarkılar bulunuyor…";
      const r = await resolveSongRefs(entries.flatMap((e) => e.songIds));
      resolved = r.ids;
      const total = entries.reduce((n, e) => n + e.songIds.length, 0);
      msg.textContent = `${entries.length} repertuar · ${total - r.missing.length}/${total} şarkı bulundu${r.missing.length ? ` · bulunamayanlar repertuara eklenmez` : ""}.`;
      preview.innerHTML = entries.map((e) => {
        const miss = e.songIds.filter((x) => !resolved.has(x.trim()));
        return `<div class="row"><span class="row-body"><span class="row-title">${esc(e.name)}</span><span class="row-sub">${e.songIds.length - miss.length} şarkı${miss.length ? ` · bulunamadı: ${miss.map(esc).join(", ")}` : ""}</span></span></div>`;
      }).join("");
      start.disabled = entries.length === 0;
    } catch (e) {
      msg.textContent = "Geçersiz JSON: " + (e as Error).message;
    }
  });
  start.addEventListener("click", async () => {
    if (!username) { msg.textContent = "Önce Hesabım sayfasından kullanıcı adını seç."; return; }
    start.disabled = true;
    file.disabled = true;
    try {
      const out = entries.map((e) => ({ name: e.name, songIds: [...new Set(e.songIds.map((x) => resolved.get(x.trim())).filter((x): x is string => Boolean(x)))] }));
      const ok = await createPublicRepertoires(me.uid, username, out, (n) => { msg.textContent = `Yükleniyor… ${n}/${out.length}`; });
      msg.textContent = `${ok} repertuar herkese açık olarak eklendi.`;
    } catch (e) {
      msg.textContent = "Yüklenemedi: " + (e as Error).message;
    }
    file.disabled = false;
    file.value = "";
    preview.innerHTML = "";
  });
}

(async () => {
  if (!firebaseReady) { status.textContent = "Web girişi yapılandırılmamış."; return; }
  const user = await currentUser();
  if (!user) { $("admin-auth").hidden = false; status.textContent = ""; return; }
  me = user;
  const admin = await apiIsAdmin(user);
  if (admin === null) { status.textContent = "Sunucuya ulaşılamadı. Bağlantını kontrol edip sayfayı yenile."; return; }
  if (!admin) { $("admin-denied").hidden = false; status.textContent = ""; return; }
  $("admin-pending").hidden = false;
  $("admin-reports").hidden = false;
  $("admin-pro").hidden = false;
  $("admin-import").hidden = false;
  $("admin-bulk").hidden = false;
  $("admin-refresh").hidden = false;
  setupProForm();
  const username = (await getProfile(user.uid).catch(() => null))?.username ?? "";
  setupSongImport(username || user.displayName || "");
  setupBulkImport(username);
  status.textContent = "";
  $("report-filter").querySelectorAll<HTMLButtonElement>("[data-f]").forEach((b) =>
    b.addEventListener("click", () => {
      reportFilter = b.dataset.f as "open" | "closed";
      $("report-filter").querySelectorAll(".chip").forEach((c) => c.classList.toggle("active", c === b));
      loadReports();
    }),
  );
  const refresh = () => Promise.all([loadPending(), loadReports(), loadPro()]).catch((e) => { status.textContent = "Yüklenemedi: " + ((e as Error).message ?? e); });
  $("admin-refresh").addEventListener("click", refresh);
  await refresh();
})();
