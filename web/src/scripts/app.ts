// Her sayfada çalışır: gece modu, mobil menü, giriş durumu, Plus bayrağı, reklam yükleme.
import { firebaseReady, onUser, refreshPlus, isAdminUser } from "../lib/firebase-client.ts";
import { ADSENSE_CLIENT } from "../lib/site.ts";

const html = document.documentElement;

// Gece modu — düğme alt bilgide; etiketi geçerli temaya göre değişir
const themeBtn = document.getElementById("theme-toggle");
function isDark(): boolean {
  const current = html.getAttribute("data-theme");
  return current ? current === "dark" : window.matchMedia("(prefers-color-scheme: dark)").matches;
}
function syncThemeLabel() { if (themeBtn) themeBtn.textContent = isDark() ? "Aydınlık tema" : "Gece modu"; }
themeBtn?.addEventListener("click", () => {
  const next = isDark() ? "light" : "dark";
  html.setAttribute("data-theme", next);
  try { localStorage.setItem("gituar-theme", next); } catch {}
  syncThemeLabel();
});
syncThemeLabel();

// Mobil menü (üst bardaki ☰)
const menuBtn = document.getElementById("menu-toggle");
const menu = document.getElementById("header-menu");
menuBtn?.addEventListener("click", () => {
  const open = menu?.classList.toggle("open") ?? false;
  menuBtn.setAttribute("aria-expanded", String(open));
});
document.addEventListener("click", (e) => {
  if (!menu?.classList.contains("open")) return;
  if (menu.contains(e.target as Node) || menuBtn?.contains(e.target as Node)) return;
  menu.classList.remove("open");
  menuBtn?.setAttribute("aria-expanded", "false");
});

// "/" tuşu aramaya odaklanır (Repertuarım alışkanlığı)
document.addEventListener("keydown", (e) => {
  if (e.key !== "/" || e.metaKey || e.ctrlKey || e.altKey) return;
  const target = e.target as HTMLElement | null;
  if (target && /^(INPUT|TEXTAREA)$/.test(target.tagName)) return;
  const input = document.querySelector<HTMLInputElement>("#q, .search-big input, .search-mini input");
  if (input) { e.preventDefault(); input.focus(); }
});

// Giriş durumu → üst bar; Plus durumu → reklamlar
let adsLoaded = false;
const authBtns = [document.getElementById("auth-btn"), document.getElementById("auth-btn-mobile")].filter(Boolean) as HTMLAnchorElement[];
// Daha önce giriş yapmamış ziyaretçide Firebase SDK hiç indirilmez (sayfa hızı).
let hadSession = false;
try { hadSession = localStorage.getItem("gituar-auth") === "1"; } catch {}
if (firebaseReady && hadSession) {
  onUser((user) => {
    for (const btn of authBtns) {
      btn.textContent = user ? user.displayName?.split(" ")[0] || "Hesabım" : "Giriş yap";
      btn.href = user ? "/repertuarlarim/" : "/giris/";
    }
    if (user) refreshPlus(user.uid).then((plus) => { if (!plus) loadAds(); });
    else loadAds();
    // Yönetim bağlantısı yalnızca admin hesaplarda (users/{uid}.isAdmin)
    const adminLinks = [document.getElementById("admin-link"), document.getElementById("admin-link-mobile")].filter(Boolean) as HTMLElement[];
    if (user) isAdminUser(user.uid).then((admin) => { for (const el of adminLinks) el.hidden = !admin; });
    else for (const el of adminLinks) el.hidden = true;
  });
} else {
  loadAds();
}

function loadAds() {
  if (adsLoaded || !ADSENSE_CLIENT || html.classList.contains("plus")) return;
  adsLoaded = true;
  const s = document.createElement("script");
  s.async = true;
  s.crossOrigin = "anonymous";
  s.src = `https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=${ADSENSE_CLIENT}`;
  s.onload = () => {
    const w = window as unknown as { adsbygoogle?: unknown[] };
    document.querySelectorAll<HTMLElement>("ins.adsbygoogle").forEach(() => {
      (w.adsbygoogle = w.adsbygoogle || []).push({});
    });
  };
  document.head.appendChild(s);
}
