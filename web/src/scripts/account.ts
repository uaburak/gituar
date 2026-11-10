// Hesabım: bilgiler, çıkış yap, hesabı sil (yeniden doğrulama gerekiyorsa şifre ya da Google penceresi).
import { firebaseReady, currentUser, signOutUser, deleteAccount, reauthenticate, ReauthRequired, refreshPro } from "../lib/firebase-client.ts";
import { API_URL } from "../lib/site.ts";
import { getProfile, saveProfile, isUsernameTaken, cleanUsername, unblockUser, usernameOf } from "../lib/user-data.ts";
import { esc } from "../lib/search-client.ts";

const $ = <T extends HTMLElement = HTMLElement>(id: string) => document.getElementById(id) as T;
const status = $("acc-status");

(async () => {
  if (!firebaseReady) { status.textContent = "Web girişi yapılandırılmamış."; return; }
  const user = await currentUser();
  if (!user) { $("acc-auth").hidden = false; status.textContent = ""; return; }
  status.textContent = "";
  const params = new URL(location.href).searchParams;
  const next = params.get("next");
  let profile = await getProfile(user.uid).catch(() => undefined);
  if (profile === null || (profile && !profile.username)) {
    // iOS CompleteProfileView ile aynı: ad, soyad, benzersiz kullanıcı adı
    await completeProfile(user);
    profile = await getProfile(user.uid).catch(() => undefined);
    if (next) { location.href = next; return; }
  }
  $("acc-main").hidden = false;
  $("acc-name").textContent = profile ? `${profile.firstName} ${profile.lastName}`.trim() || user.displayName || "–" : user.displayName || "–";
  if (profile?.username) {
    const a = $<HTMLAnchorElement>("acc-username");
    a.textContent = "@" + profile.username;
    a.href = `/kullanici/${encodeURIComponent(profile.username)}/`;
  }
  void renderBlocked(user.uid, profile?.blockedUsers ?? []);
  $("acc-email").textContent = user.email || "–";
  refreshPro(user.uid).then((pro) => { $("acc-pro").textContent = pro ? "Aktif" : "Yok"; }).catch(() => {});

  $("btn-signout").addEventListener("click", async () => {
    await signOutUser();
    location.href = "/";
  });

  const confirmBox = $<HTMLInputElement>("del-confirm");
  const delBtn = $<HTMLButtonElement>("btn-delete");
  const err = $("del-error");
  const passWrap = $("del-password");
  const pass = $<HTMLInputElement>("del-pass");
  confirmBox.addEventListener("change", () => { delBtn.disabled = !confirmBox.checked; });

  delBtn.addEventListener("click", async () => {
    if (!confirmBox.checked) return;
    if (!confirm("Hesabın ve bütün verilerin kalıcı olarak silinecek. Emin misin?")) return;
    err.hidden = true;
    delBtn.disabled = true;
    delBtn.textContent = "Siliniyor…";
    try {
      // Şifre istendiyse önce yeniden doğrula
      if (!passWrap.hidden) await reauthenticate(user, pass.value);
      await deleteAccount(user, API_URL);
      location.href = "/?hesap=silindi";
    } catch (e) {
      delBtn.disabled = false;
      delBtn.textContent = "Hesabımı kalıcı olarak sil";
      if (e instanceof ReauthRequired) {
        if (e.method === "password") {
          passWrap.hidden = false;
          pass.focus();
          err.textContent = "Güvenlik için şifreni tekrar gir ve silme düğmesine yeniden bas.";
        } else {
          try {
            await reauthenticate(user);
            err.textContent = "Doğrulandı. Silmek için düğmeye tekrar bas.";
          } catch {
            err.textContent = `${e.method === "apple" ? "Apple" : "Google"} ile doğrulama tamamlanmadı. Tekrar dene.`;
          }
        }
      } else {
        const code = (e as { code?: string }).code ?? "";
        err.textContent = code === "auth/wrong-password" || code === "auth/invalid-credential" ? "Şifre yanlış." : `Silinemedi: ${(e as Error).message}`;
      }
      err.hidden = false;
    }
  });
})();

async function renderBlocked(uid: string, ids: string[]) {
  const list = $("acc-blocked");
  if (!ids.length) { list.innerHTML = `<li class="muted small">Engellenen kullanıcı bulunmuyor.</li>`; return; }
  const names = await Promise.all(ids.map((id) => usernameOf(id)));
  list.innerHTML = ids
    .map((id, i) => `<li class="acc-row"><span>${names[i] ? `@${esc(names[i]!)}` : `<span class="muted small">${esc(id)}</span>`}</span><button class="btn btn-mini" type="button" data-uid="${esc(id)}">Engeli Kaldır</button></li>`)
    .join("");
  list.querySelectorAll<HTMLButtonElement>("[data-uid]").forEach((b) =>
    b.addEventListener("click", async () => {
      b.disabled = true;
      try {
        await unblockUser(uid, b.dataset.uid!);
        await renderBlocked(uid, ids.filter((x) => x !== b.dataset.uid));
      } catch {
        b.disabled = false;
        alert("Engel kaldırılamadı, tekrar dene.");
      }
    }),
  );
}

/** Profil formu; kaydedilince çözülür. */
function completeProfile(user: import("firebase/auth").User): Promise<void> {
  $("acc-complete").hidden = false;
  const first = $<HTMLInputElement>("pf-first"), last = $<HTMLInputElement>("pf-last"), name = $<HTMLInputElement>("pf-user");
  const msg = $("pf-user-msg"), save = $<HTMLButtonElement>("pf-save"), err = $("pf-error");
  const parts = (user.displayName ?? "").trim().split(/\s+/).filter(Boolean);
  if (parts.length > 1) { first.value = parts.slice(0, -1).join(" "); last.value = parts.at(-1)!; }
  else if (parts.length === 1) first.value = parts[0];
  let available = false;
  let timer = 0;
  const validate = () => { save.disabled = !(first.value.trim() && last.value.trim() && name.value.length >= 3 && available); };
  name.addEventListener("input", () => {
    const cleaned = cleanUsername(name.value);
    if (cleaned !== name.value) name.value = cleaned;
    available = false;
    validate();
    clearTimeout(timer);
    if (cleaned.length < 3) { msg.textContent = "en az 3 karakter"; return; }
    msg.textContent = "kontrol ediliyor…";
    timer = window.setTimeout(async () => {
      try {
        const taken = await isUsernameTaken(cleaned, user.uid);
        if (cleaned !== name.value) return;
        available = !taken;
        msg.textContent = taken ? "bu kullanıcı adı daha önce alınmış" : "uygun";
      } catch {
        msg.textContent = "kontrol edilemedi";
      }
      validate();
    }, 500);
  });
  first.addEventListener("input", validate);
  last.addEventListener("input", validate);
  return new Promise((resolve) => {
    $<HTMLFormElement>("profile-form").addEventListener("submit", async (e) => {
      e.preventDefault();
      if (save.disabled) return;
      save.disabled = true;
      save.textContent = "Kaydediliyor…";
      err.hidden = true;
      try {
        if (await isUsernameTaken(name.value, user.uid)) { available = false; msg.textContent = "bu kullanıcı adı daha önce alınmış"; throw new Error("Kullanıcı adı alınmış"); }
        await saveProfile(user.uid, { firstName: first.value, lastName: last.value, username: name.value, email: user.email, photoUrl: user.photoURL });
        $("acc-complete").hidden = true;
        resolve();
      } catch (e2) {
        err.textContent = "Profil kaydedilemedi: " + (e2 as Error).message;
        err.hidden = false;
        save.textContent = "Tamamla";
        validate();
      }
    });
  });
}
