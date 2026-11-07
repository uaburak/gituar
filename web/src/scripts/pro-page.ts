import { firebaseReady, currentUser, refreshPro } from "../lib/firebase-client.ts";
const active = document.getElementById("pro-active")!;
async function check() {
  if (!firebaseReady) return;
  const user = await currentUser();
  if (!user) { location.href = "/giris/?next=/pro/"; return; }
  const pro = await refreshPro(user.uid);
  active.hidden = !pro;
  if (!pro) alert("Bu hesapta aktif Pro görünmüyor. iPhone'da Profil → Gituar Pro'dan abone olduktan sonra tekrar dene.");
}
document.getElementById("pro-refresh")!.addEventListener("click", check);
if (document.documentElement.classList.contains("pro")) active.hidden = false;
