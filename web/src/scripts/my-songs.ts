// Şarkılarım: liste, ekleme, düzenleme, silme (iOS MySongsView / EditSongView ile aynı kurallar).
//  - "Taslak Kaydet": draft · "Yayınla": pending (yönetici gönderirse doğrudan yayında)
//  - Yayındaki şarkı düzenlenince "Kaydet" (API yayında tutar)
//  - İlk yayından önce "Paylaşmadan önce" kuralları kabul edilir; içerik uygunsuz kelime filtresinden geçer
import type { User } from "firebase/auth";
import { firebaseReady, currentUser } from "../lib/firebase-client.ts";
import { getProfile } from "../lib/user-data.ts";
import { listMySongs, createSong, updateSong, removeSong, STATUS_LABEL, type MySong, type SongStatus } from "../lib/my-songs.ts";
import { firstObjectionableWord } from "../lib/content-filter.ts";
import { esc } from "../lib/search-client.ts";

const $ = <T extends HTMLElement = HTMLElement>(id: string) => document.getElementById(id) as T;
const TERMS_KEY = "gituar-ugc-terms";
const status = $("ms-status");
let me: User;
let username = "";
let songs: MySong[] = [];
let editing: MySong | null = null;

const BADGE: Record<SongStatus, string> = { approved: "ms-b-green", pending: "ms-b-orange", draft: "ms-b-gray", rejected: "ms-b-red" };

function renderList() {
  $("ms-list").innerHTML = songs
    .map((s) => `<li><button type="button" class="row ms-row" data-id="${esc(s.id)}">
      <span class="rp-text"><span class="row-title">${esc(s.title)}</span><span class="row-note"> · ${esc(s.artist)}${s.originalKey ? ` · ${esc(s.originalKey)}` : ""}</span></span>
      <span class="ms-badge ${BADGE[s.status] ?? "ms-b-gray"}">${STATUS_LABEL[s.status] ?? s.status}</span></button></li>`)
    .join("");
  $("ms-empty").hidden = songs.length > 0;
  $("ms-meta").textContent = songs.length ? `${songs.length} şarkı · iPhone'daki Gituar ile aynı liste` : "iPhone'daki Gituar ile aynı liste";
  $("ms-list").querySelectorAll<HTMLButtonElement>("[data-id]").forEach((b) =>
    b.addEventListener("click", () => openEditor(songs.find((s) => s.id === b.dataset.id) ?? null)),
  );
}

async function load() {
  status.textContent = "Yükleniyor…";
  try {
    songs = await listMySongs(me);
    status.textContent = "";
    renderList();
  } catch (e) {
    status.textContent = "Şarkılar yüklenemedi: " + (e as Error).message;
  }
}

function setUrl(id: string | null) {
  const q = id === "" ? "?yeni" : id ? `?id=${encodeURIComponent(id)}` : "";
  history.replaceState(null, "", location.pathname + q);
}

function openEditor(song: MySong | null) {
  editing = song;
  const form = $<HTMLFormElement>("ed-form");
  form.reset();
  $("ed-error").hidden = true;
  $("ed-title").textContent = song ? "Şarkıyı Düzenle" : "Yeni Şarkı Oluştur";
  $("ed-sub").textContent = song ? "Şarkında yapmak istediğin değişiklikleri yap." : "Şarkının sözlerini ve akorlarını aşağıya ekle.";
  $<HTMLInputElement>("ed-name").value = song?.title ?? "";
  $<HTMLInputElement>("ed-artist").value = song?.artist ?? "";
  const key = $<HTMLSelectElement>("ed-key");
  if (song?.originalKey && ![...key.options].some((o) => o.value === song.originalKey)) key.add(new Option(song.originalKey, song.originalKey));
  key.value = song?.originalKey || "C";
  $<HTMLTextAreaElement>("ed-content").value = song?.content ?? "";
  const st = song?.status;
  const line = $("ed-status");
  line.hidden = !st;
  if (st) line.innerHTML = `<span class="ms-badge ${BADGE[st]}">${STATUS_LABEL[st]}</span> ${st === "pending" ? "Şarkın editör onayı bekliyor." : st === "approved" ? `Yayında. <a href="/akor/${esc(song!.artistSlug)}/${esc(song!.slug)}/">Şarkı sayfasını aç ›</a>` : st === "rejected" ? "Şarkın onaylanmadı. Düzenleyip yeniden gönderebilirsin." : "Taslak: yalnızca sen görüyorsun."}`;
  $("ed-draft").textContent = st === "approved" ? "Kaydet" : "Taslak Kaydet";
  $("ed-publish").hidden = st === "pending" || st === "approved";
  $("ed-delete").hidden = !song;
  $("ms-list-wrap").hidden = true;
  $("ms-editor").hidden = false;
  setUrl(song ? song.id : "");
  $<HTMLInputElement>("ed-name").focus();
}

function closeEditor() {
  editing = null;
  $("ms-editor").hidden = true;
  $("ms-list-wrap").hidden = false;
  setUrl(null);
}

function showError(msg: string) {
  $("ed-error").textContent = msg;
  $("ed-error").hidden = false;
}

async function save(target: "draft" | "pending") {
  const form = $<HTMLFormElement>("ed-form");
  if (!form.reportValidity()) return;
  const title = $<HTMLInputElement>("ed-name").value.trim();
  const artist = $<HTMLInputElement>("ed-artist").value.trim();
  const content = $<HTMLTextAreaElement>("ed-content").value.replace(/\s+$/, "");
  const originalKey = $<HTMLSelectElement>("ed-key").value;
  if (target === "pending") {
    let accepted = false;
    try { accepted = localStorage.getItem(TERMS_KEY) === "1"; } catch {}
    if (!accepted) { $<HTMLDialogElement>("terms-dialog").showModal(); return; }
  }
  if (target === "pending" && firstObjectionableWord(title, artist, content)) {
    showError("Şarkı adı, sanatçı ya da sözlerde uygunsuz bir ifade var. Küfür, hakaret ve nefret söylemi içeren içerikler yayımlanmaz.");
    return;
  }
  const buttons = form.querySelectorAll<HTMLButtonElement>("button");
  buttons.forEach((b) => (b.disabled = true));
  $("ed-error").hidden = true;
  try {
    const input = { artist, title, originalKey, content, status: target as SongStatus, addedBy: editing?.addedBy ?? username };
    if (editing) await updateSong(me, editing.id, input);
    else await createSong(me, input);
    closeEditor();
    await load();
  } catch (e) {
    showError((e as Error).message);
  } finally {
    buttons.forEach((b) => (b.disabled = false));
  }
}

(async () => {
  if (!firebaseReady) { status.textContent = "Web girişi yapılandırılmamış."; return; }
  const user = await currentUser();
  if (!user) { $("ms-auth").hidden = false; status.textContent = ""; return; }
  me = user;
  const profile = await getProfile(user.uid).catch(() => null);
  username = profile?.username ?? "";
  if (!username) $("ms-profile").hidden = false;
  $("ms-list-wrap").hidden = false;
  $("ms-new").addEventListener("click", () => {
    if (!username) { location.href = "/hesap/?tamamla=1&next=/sarkilarim/?yeni"; return; }
    openEditor(null);
  });
  $("ed-cancel").addEventListener("click", closeEditor);
  $("ed-draft").addEventListener("click", () => save("draft"));
  $("ed-publish").addEventListener("click", () => save("pending"));
  $("ed-delete").addEventListener("click", async () => {
    if (!editing || !confirm(`“${editing.title}” silinecek. Bu işlem geri alınamaz.`)) return;
    try {
      await removeSong(me, editing.id);
      closeEditor();
      await load();
    } catch (e) {
      showError((e as Error).message);
    }
  });
  $("terms-accept").addEventListener("click", () => {
    try { localStorage.setItem(TERMS_KEY, "1"); } catch {}
    $<HTMLDialogElement>("terms-dialog").close();
    void save("pending");
  });
  $("terms-cancel").addEventListener("click", () => $<HTMLDialogElement>("terms-dialog").close());
  await load();
  const params = new URL(location.href).searchParams;
  const id = params.get("id");
  if (id) openEditor(songs.find((s) => s.id === id) ?? null);
  else if (params.has("yeni") && username) openEditor(null);
})();
