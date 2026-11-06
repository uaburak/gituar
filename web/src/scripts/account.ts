// Hesabım: bilgiler, çıkış yap, hesabı sil (yeniden doğrulama gerekiyorsa şifre ya da Google penceresi).
import { firebaseReady, currentUser, signOutUser, deleteAccount, reauthenticate, ReauthRequired, refreshPlus } from "../lib/firebase-client.ts";
import { API_URL } from "../lib/site.ts";

const $ = <T extends HTMLElement = HTMLElement>(id: string) => document.getElementById(id) as T;
const status = $("acc-status");

(async () => {
  if (!firebaseReady) { status.textContent = "Web girişi yapılandırılmamış."; return; }
  const user = await currentUser();
  if (!user) { $("acc-auth").hidden = false; status.textContent = ""; return; }
  status.textContent = "";
  $("acc-main").hidden = false;
  $("acc-name").textContent = user.displayName || "–";
  $("acc-email").textContent = user.email || "–";
  refreshPlus(user.uid).then((pro) => { $("acc-pro").textContent = pro ? "Aktif" : "Yok"; }).catch(() => {});

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
            err.textContent = "Google ile doğrulama tamamlanmadı. Tekrar dene.";
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
