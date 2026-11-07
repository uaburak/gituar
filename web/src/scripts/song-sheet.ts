// Şarkı sayfası: ton şeridi, kapo, akor gizle, yazı boyutu, otomatik kaydırma, ton kaydetme, repertuara ekle.
import { transpose, semitoneOffset, prefersFlats, chordSpans } from "@shared/chords";
import { esc, songExists } from "../lib/search-client.ts";
import { trackAction } from "../lib/actions.ts";
import { simplifyChord, chordShapes } from "../lib/chord-theory.ts";
import { chordSvg } from "../lib/chord-svg.ts";

const root = document.getElementById("song");
if (root) {
  init(root);
  checkRemoved(root.dataset.id ?? "");
}

/**
 * Şarkı API'de yoksa (silindi ya da yayından kalktı) site yeniden derlenene kadar içerik burada gizlenir.
 * Varsa sayfa görüntülenmesi popülerliğe bir kez sayılır (aynı kişi/cihaz için tekrar sayılmaz).
 */
async function checkRemoved(id: string) {
  if (!id) return;
  try {
    if (await songExists(id)) { trackAction(id, "view"); return; }
    const meta = document.createElement("meta");
    meta.name = "robots";
    meta.content = "noindex";
    document.head.appendChild(meta);
    document.querySelectorAll("#song, .song-chords, .song-intro, .song-more, .song-ads").forEach((el) => el.remove());
    const note = document.createElement("div");
    note.className = "alert";
    note.innerHTML = 'Bu içerik kaldırıldı. Sorunun varsa <a href="/iletisim/">bizimle iletişime geç</a>.';
    document.querySelector(".song-head")?.after(note);
  } catch {}
}

function init(root: HTMLElement) {
  const songId = root.dataset.id ?? "";
  // Son çaldıklarım (ana sayfa): en son 20 şarkı, yalnızca bu tarayıcıda
  try {
    const recent: { p: string; a: string; s: string }[] = JSON.parse(localStorage.getItem("gituar-recent") ?? "[]");
    const entry = { p: location.pathname, a: root.dataset.artist ?? "", s: root.dataset.name ?? "" };
    localStorage.setItem("gituar-recent", JSON.stringify([entry, ...recent.filter((r) => r.p !== entry.p)].slice(0, 20)));
  } catch {}
  const originalKey = root.dataset.key ?? "C";
  const originalRoot = root.dataset.root ?? "C";
  const sheet = document.getElementById("sheet")!;
  const pre = document.getElementById("chords")!;
  const lines = [...pre.querySelectorAll<HTMLElement>(".line")].map((el) => ({ el, text: (el.textContent ?? "").replace(/\n$/, ""), chord: el.dataset.c === "1" }));
  const $ = <T extends HTMLElement = HTMLElement>(id: string) => document.getElementById(id) as T;
  // Ton şeridi: her ton bir düğme (eşsesli yazımlar dahil); seçili olan vurgulu, orijinal olan çerçeveli.
  const keyButtons = [...root.querySelectorAll<HTMLButtonElement>(".rp-keys button[data-k]")];
  const keySuffix = (originalKey ?? "").trim().slice(originalRoot.length);

  const prefKey = `gituar-pref-${songId}`;
  let saved: { key: string; capo: number } | null = null;
  try { saved = JSON.parse(localStorage.getItem(prefKey) ?? "null"); } catch {}
  let selected = saved?.key ?? originalRoot;
  let capo = saved?.capo ?? 0;
  let fontSize = Number(localStorage.getItem("gituar-font") ?? 13) || 13;

  function highlight(text: string): string {
    let html = "";
    let cursor = 0;
    for (const sp of chordSpans(text)) {
      html += esc(text.slice(cursor, sp.start)) + `<b class="chord">${esc(sp.chord)}</b>`;
      cursor = sp.end;
    }
    return html + esc(text.slice(cursor));
  }

  function render() {
    const offset = semitoneOffset(originalKey, selected) - capo;
    const flats = prefersFlats(selected, originalKey);
    for (const l of lines) {
      if (!l.chord) continue;
      l.el.innerHTML = highlight(transpose(l.text, offset, flats)) + "\n";
    }
    for (const b of keyButtons) b.setAttribute("aria-pressed", b.dataset.k === selected ? "true" : "false");
    $("key-label").textContent = selected + keySuffix;
    const isOriginal = selected === originalRoot;
    // Orijinal ton ve kapo 0: akor adları Pro renginde
    sheet.classList.toggle("is-original", isOriginal && capo === 0);
    $("capo-val").textContent = String(capo);
    $("font-val").textContent = String(fontSize);
    sheet.style.setProperty("--sheet-font", `${fontSize}px`);
    const modified = selected !== originalRoot || capo !== 0;
    $("btn-reset").hidden = !modified;
    $("btn-save").hidden = !modified || (saved?.key === selected && saved?.capo === capo);
    $("btn-saved").hidden = !saved;
    if (saved) {
      const label = `Kayıtlı tona dön: ${saved.key + keySuffix}${saved.capo ? ` · kapo ${saved.capo}` : ""}`;
      $("btn-saved").title = label;
      $("btn-saved").textContent = `Kayıtlı Ton: ${saved.key + keySuffix}${saved.capo ? ` · ${saved.capo}` : ""}`;
    }
    if (typeof updatePlayVisibility === "function") requestAnimationFrame(updatePlayVisibility);
  }

  for (const b of keyButtons) b.addEventListener("click", () => { selected = b.dataset.k!; render(); });
  // Menü: ton şeridini ve akor diyagramlarını aç/kapat
  for (const [btnId, panelId] of [["menu-keys", "key-strip"], ["menu-diagrams", "diagram-panel"]] as const) {
    const btn = $(btnId), panel = $(panelId);
    btn.addEventListener("click", () => { panel.hidden = !panel.hidden; btn.setAttribute("aria-expanded", String(!panel.hidden)); });
  }
  $("capo-dec").addEventListener("click", () => { capo = Math.max(0, capo - 1); render(); });
  $("capo-inc").addEventListener("click", () => { capo = Math.min(9, capo + 1); render(); });
  $("font-dec").addEventListener("click", () => { fontSize = Math.max(10, fontSize - 1); persistFont(); render(); });
  $("font-inc").addEventListener("click", () => { fontSize = Math.min(30, fontSize + 1); persistFont(); render(); });
  $("btn-chords").addEventListener("click", () => requestAnimationFrame(updatePlayVisibility));
  $("btn-reset").addEventListener("click", () => { selected = originalRoot; capo = 0; render(); });
  $("btn-saved").addEventListener("click", () => { if (saved) { selected = saved.key; capo = saved.capo; render(); } });
  $("btn-save").addEventListener("click", () => {
    saved = { key: selected, capo };
    try { localStorage.setItem(prefKey, JSON.stringify(saved)); } catch {}
    render();
  });
  $("btn-print").addEventListener("click", () => window.print());
  const chordsBtn = $("btn-chords");
  chordsBtn.addEventListener("click", () => {
    const hidden = sheet.classList.toggle("hide-chords");
    chordsBtn.setAttribute("aria-pressed", hidden ? "false" : "true");
    chordsBtn.textContent = hidden ? "Akorları Aç" : "Akorları Kapat";
  });
  function persistFont() { try { localStorage.setItem("gituar-font", String(fontSize)); } catch {} }

  // ---- Akor balonu: kâğıttaki akorun üstüne gelince diyagramı ----
  const pop = document.createElement("div");
  pop.className = "chord-pop";
  pop.hidden = true;
  pop.setAttribute("role", "tooltip");
  document.body.appendChild(pop);
  let popFor: HTMLElement | null = null;
  pre.addEventListener("pointerover", (e) => {
    const el = (e.target as HTMLElement).closest<HTMLElement>(".chord");
    if (!el || el === popFor || e.pointerType === "touch") return;
    const name = el.textContent ?? "";
    const c = simplifyChord(name);
    const shape = c ? chordShapes(c.root, c.quality)[0] : undefined;
    if (!shape) { pop.hidden = true; popFor = null; return; }
    popFor = el;
    pop.innerHTML = chordSvg(shape, `${name} akoru`) + `<span class="cd-label">${esc(name)}</span>`;
    pop.hidden = false;
    const r = el.getBoundingClientRect();
    const pw = pop.offsetWidth, ph = pop.offsetHeight;
    const above = r.top - ph - 8 > 0;
    const left = Math.min(Math.max(8, r.left + r.width / 2 - pw / 2), window.innerWidth - pw - 8);
    pop.style.left = `${left + window.scrollX}px`;
    pop.style.top = `${(above ? r.top - ph - 8 : r.bottom + 8) + window.scrollY}px`;
  });
  pre.addEventListener("pointerout", (e) => {
    const to = e.relatedTarget as HTMLElement | null;
    if (popFor && to && popFor.contains(to)) return;
    if ((e.target as HTMLElement).closest(".chord")) { pop.hidden = true; popFor = null; }
  });
  window.addEventListener("scroll", () => { if (!pop.hidden) { pop.hidden = true; popFor = null; } }, { passive: true });

  // ---- Sayfayı oynat (otomatik kaydırma) ----
  // Yalnızca akor bölgesini kaydırır: akorların üstünden başlar, akorların altı görününce durur.
  // Akorlar ekrana sığıyorsa buton hiç gösterilmez.
  const playBtn = $("btn-play");
  const bar = $("play-bar");
  const speedInput = $<HTMLInputElement>("play-speed");
  let playing = false;
  let paused = false;
  let raf = 0;
  let last = 0;
  let carry = 0;
  let wakeLock: { release(): Promise<void> } | null = null;
  const pxPerSecond = () => Number(speedInput.value) * 6;
  const headerH = () => { const h = document.querySelector<HTMLElement>(".site-header"); if (!h) return 0; const pos = getComputedStyle(h).position; return pos === "sticky" || pos === "fixed" ? h.offsetHeight : 0; };
  const bottomMargin = 24;

  function sheetFits(): boolean {
    return sheet.offsetHeight <= window.innerHeight - headerH() - bottomMargin;
  }
  // Oynat düğmesi her zaman görünür; akorlar ekrana sığıyorsa kaydırma hemen sonda durur.
  function updatePlayVisibility() {
    if (playing && sheetFits()) stop();
  }
  function sheetBottomReached(): boolean {
    return sheet.getBoundingClientRect().bottom <= window.innerHeight - bottomMargin;
  }

  function step(now: number) {
    if (!playing) return;
    if (!paused) {
      const dt = (now - last) / 1000;
      carry += pxPerSecond() * dt;
      const px = Math.floor(carry);
      if (px > 0) { window.scrollBy(0, px); carry -= px; }
      if (sheetBottomReached()) setPaused(true);
    }
    last = now;
    raf = requestAnimationFrame(step);
  }
  function setPaused(p: boolean) { paused = p; $("play-toggle").textContent = p ? "Devam" : "Durdur"; }
  async function start() {
    // Akorların üstü üst barın altına gelsin; zaten aşağıdaysa kaldığı yerden sürsün
    const top = sheet.getBoundingClientRect().top + window.scrollY - headerH() - 8;
    if (window.scrollY < top) window.scrollTo({ top, behavior: "smooth" });
    playing = true; paused = false; last = performance.now(); carry = 0;
    bar.classList.add("active"); playBtn.setAttribute("aria-pressed", "true"); playBtn.textContent = "Durdur"; setPaused(false);
    raf = requestAnimationFrame(step);
    try { wakeLock = await (navigator as unknown as { wakeLock?: { request(t: string): Promise<{ release(): Promise<void> }> } }).wakeLock?.request("screen") ?? null; } catch {}
  }
  function stop() {
    playing = false; cancelAnimationFrame(raf);
    bar.classList.remove("active"); playBtn.setAttribute("aria-pressed", "false"); playBtn.textContent = "Sayfayı Oynat";
    wakeLock?.release().catch(() => {}); wakeLock = null;
  }
  playBtn.addEventListener("click", () => (playing ? stop() : start()));
  $("play-toggle").addEventListener("click", () => {
    // Sona gelmişse "Devam" akorların başına döner
    if (paused && sheetBottomReached()) window.scrollTo({ top: sheet.getBoundingClientRect().top + window.scrollY - headerH() - 8 });
    setPaused(!paused);
  });
  $("play-close").addEventListener("click", stop);
  document.addEventListener("visibilitychange", () => { if (document.hidden && playing) setPaused(true); });
  window.addEventListener("resize", updatePlayVisibility);
  updatePlayVisibility();

  // ---- Repertuara ekle (Firebase yalnızca burada yüklenir) ----
  const dialog = $<HTMLDialogElement>("rep-dialog");
  $("btn-rep").addEventListener("click", async () => {
    const mod = await import("../lib/firebase-client.ts");
    if (!mod.firebaseReady) { alert("Repertuarlar için web girişi yakında. Şimdilik iPhone uygulamasını kullanabilirsin."); return; }
    const user = await mod.currentUser();
    if (!user) { location.href = `/giris/?next=${encodeURIComponent(location.pathname)}`; return; }
    const list = $("rep-list");
    list.innerHTML = `<div class="row muted small">Yükleniyor…</div>`;
    dialog.showModal();
    const reps = await mod.listMyRepertoires(user.uid);
    list.innerHTML = reps.length
      ? reps.map((r) => `<button type="button" class="row" data-rep="${esc(r.id)}" data-public="${r.isPublic ? "1" : ""}" style="width:100%;border:0;background:none;cursor:pointer;text-align:left"><span class="row-body"><span class="row-title">${esc(r.name)}</span><span class="row-sub">${r.songIds.length} şarkı${r.isPublic ? " · herkese açık" : ""}${r.songIds.includes(songId) ? " · ekli" : ""}</span></span></button>`).join("")
      : `<div class="row muted small">Henüz repertuar yok. Aşağıdan oluştur.</div>`;
    list.querySelectorAll<HTMLButtonElement>("[data-rep]").forEach((b) =>
      b.addEventListener("click", async () => {
        b.disabled = true;
        await mod.addSongToRepertoire(user.uid, { id: b.dataset.rep!, isPublic: b.dataset.public === "1" }, songId);
        trackAction(songId, "repertoire", { token: await user.getIdToken() });
        dialog.close();
        alert("Repertuara eklendi.");
      }),
    );
    const form = $<HTMLFormElement>("rep-new");
    form.onsubmit = async (e) => {
      e.preventDefault();
      const name = (new FormData(form).get("name") as string).trim();
      if (!name) return;
      const id = await mod.createRepertoire(user.uid, name);
      await mod.addSongToRepertoire(user.uid, { id, isPublic: false }, songId);
      trackAction(songId, "repertoire", { token: await user.getIdToken() });
      dialog.close();
      alert(`"${name}" oluşturuldu ve şarkı eklendi.`);
    };
  });
  $("rep-close").addEventListener("click", () => dialog.close());

  // ---- Şikayet Et (iOS ile aynı nedenler ve metinler; Firestore reports koleksiyonu) ----
  const reportDialog = $<HTMLDialogElement>("report-dialog");
  const showReportResult = (ok: boolean) => {
    $("report-ask").hidden = true;
    $("report-done").hidden = false;
    $("report-done-title").textContent = ok ? "Şikayet Alındı" : "Şikayet Gönderilemedi";
    $("report-done-text").textContent = ok
      ? "Bildiriminiz için teşekkürler. İçerik en kısa sürede inceleme ekibimiz tarafından kontrol edilecektir."
      : "Şikayet gönderilirken bir hata oluştu. İnternet bağlantınızı kontrol edip tekrar deneyin.";
  };
  const openReport = async () => {
    const mod = await import("../lib/firebase-client.ts");
    const user = mod.firebaseReady ? await mod.currentUser() : null;
    if (!user) { location.href = `/giris/?next=${encodeURIComponent(location.pathname)}`; return; }
    $("report-ask").hidden = false;
    $("report-done").hidden = true;
    reportDialog.showModal();
    reportDialog.querySelectorAll<HTMLButtonElement>(".report-reason").forEach((b) => {
      b.disabled = false;
      b.onclick = async () => {
        reportDialog.querySelectorAll<HTMLButtonElement>(".report-reason").forEach((x) => (x.disabled = true));
        try {
          await mod.createReport(user.uid, { id: songId, name: root.dataset.name ?? "", artist: root.dataset.artist ?? "" }, b.dataset.reason!);
          showReportResult(true);
        } catch {
          showReportResult(false);
        }
      };
    });
  };
  $("report-open").addEventListener("click", openReport);
  document.getElementById("report-open-2")?.addEventListener("click", openReport);
  $("report-cancel").addEventListener("click", () => reportDialog.close());
  $("report-ok").addEventListener("click", () => reportDialog.close());

  render();
}
