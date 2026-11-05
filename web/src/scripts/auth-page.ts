import { firebaseReady, onUser, signInGoogle, signInEmail, signUpEmail, signOutUser } from "../lib/firebase-client.ts";

const $ = (id: string) => document.getElementById(id)!;
const next = new URL(location.href).searchParams.get("next") || "/repertuarlarim/";
($("next-link") as HTMLAnchorElement).href = next;
const form = $("email-form") as HTMLFormElement;
const errorBox = $("auth-error");

function showError(e: unknown) {
  const code = (e as { code?: string })?.code ?? "";
  const map: Record<string, string> = {
    "auth/invalid-credential": "E-posta ya da şifre hatalı.",
    "auth/user-not-found": "Bu e-posta ile hesap yok.",
    "auth/wrong-password": "Şifre hatalı.",
    "auth/email-already-in-use": "Bu e-posta zaten kayıtlı.",
    "auth/weak-password": "Şifre en az 6 karakter olmalı.",
    "auth/popup-closed-by-user": "Google penceresi kapatıldı.",
  };
  errorBox.textContent = map[code] ?? "Bir sorun oluştu, tekrar dene.";
  errorBox.hidden = false;
}

if (!firebaseReady) {
  $("auth-unavailable").hidden = false;
  form.hidden = true;
  $("btn-google").hidden = true;
} else {
  onUser((user) => {
    const signedIn = Boolean(user);
    $("signed-in").hidden = !signedIn;
    form.hidden = signedIn;
    $("btn-google").hidden = signedIn;
    if (user) $("signed-email").textContent = user.email ?? user.displayName ?? "";
  });
  $("btn-google").addEventListener("click", async () => { try { await signInGoogle(); location.href = next; } catch (e) { showError(e); } });
  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    const fd = new FormData(form);
    try { await signInEmail(String(fd.get("email")), String(fd.get("password"))); location.href = next; } catch (err) { showError(err); }
  });
  $("btn-signup").addEventListener("click", async () => {
    const fd = new FormData(form);
    if (!form.reportValidity()) return;
    try { await signUpEmail(String(fd.get("email")), String(fd.get("password"))); location.href = next; } catch (err) { showError(err); }
  });
  $("btn-signout").addEventListener("click", async () => { await signOutUser(); location.reload(); });
}
