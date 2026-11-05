import { firebaseReady, currentUser, refreshPlus } from "../lib/firebase-client.ts";
const active = document.getElementById("plus-active")!;
async function check() {
  if (!firebaseReady) return;
  const user = await currentUser();
  if (!user) { location.href = "/giris/?next=/plus/"; return; }
  const plus = await refreshPlus(user.uid);
  active.hidden = !plus;
  if (!plus) alert("Bu hesapta aktif Plus görünmüyor. iPhone'da Profil → Gituar Plus'tan abone olduktan sonra tekrar dene.");
}
document.getElementById("plus-refresh")!.addEventListener("click", check);
if (document.documentElement.classList.contains("plus")) active.hidden = false;
