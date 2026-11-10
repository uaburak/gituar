import { firebaseReady, onUser, currentUser, signInGoogle, signInApple, signInEmail, signUpEmail, signOutUser } from "../lib/firebase-client.ts";
import { getProfile } from "../lib/user-data.ts";

const $ = (id: string) => document.getElementById(id)!;
const next = new URL(location.href).searchParams.get("next") || "/repertuarlarim/";
($("next-link") as HTMLAnchorElement).href = next;
const form = $("email-form") as HTMLFormElement;
const errorBox = $("auth-error");

/** Girişten sonra: profil (kullanıcı adı) yoksa iOS'taki gibi önce profil tamamlanır. */
async function go() {
  const user = await currentUser();
  const profile = user ? await getProfile(user.uid).catch(() => undefined) : null;
  location.href = profile === null ? `/hesap/?tamamla=1&next=${encodeURIComponent(next)}` : next;
}

function showError(e: unknown) {
  const code = (e as { code?: string })?.code ?? "";
  const map: Record<string, string> = {
    "auth/invalid-credential": "E-posta ya da şifre hatalı.",
    "auth/user-not-found": "Bu e-posta ile hesap yok.",
    "auth/wrong-password": "Şifre hatalı.",
    "auth/email-already-in-use": "Bu e-posta zaten kayıtlı.",
    "auth/weak-password": "Şifre en az 6 karakter olmalı.",
    "auth/popup-closed-by-user": "Giriş penceresi kapatıldı.",
    "auth/operation-not-allowed": "Bu giriş yöntemi henüz açık değil.",
    "auth/account-exists-with-different-credential": "Bu e-posta başka bir giriş yöntemiyle kayıtlı; o yöntemle giriş yap.",
  };
  errorBox.textContent = map[code] ?? "Bir sorun oluştu, tekrar dene.";
  errorBox.hidden = false;
}

if (!firebaseReady) {
  $("auth-unavailable").hidden = false;
  form.hidden = true;
  $("social-btns").hidden = true;
} else {
  onUser((user) => {
    const signedIn = Boolean(user);
    $("signed-in").hidden = !signedIn;
    form.hidden = signedIn;
    $("social-btns").hidden = signedIn;
    if (user) $("signed-email").textContent = user.email ?? user.displayName ?? "";
  });
  $("btn-google").addEventListener("click", async () => { try { await signInGoogle(); await go(); } catch (e) { showError(e); } });
  $("btn-apple").addEventListener("click", async () => { try { await signInApple(); await go(); } catch (e) { showError(e); } });
  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    const fd = new FormData(form);
    try { await signInEmail(String(fd.get("email")), String(fd.get("password"))); await go(); } catch (err) { showError(err); }
  });
  $("btn-signup").addEventListener("click", async () => {
    const fd = new FormData(form);
    if (!form.reportValidity()) return;
    try { await signUpEmail(String(fd.get("email")), String(fd.get("password"))); await go(); } catch (err) { showError(err); }
  });
  $("btn-signout").addEventListener("click", async () => { await signOutUser(); location.reload(); });
}
