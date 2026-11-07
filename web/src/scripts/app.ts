// Her sayfada çalışır: gece modu, mobil menü, giriş durumu, Plus bayrağı, reklam yükleme.
import { firebaseReady, onUser, refreshPlus, isAdminUser } from "../lib/firebase-client.ts";
import { ADSENSE_CLIENT } from "../lib/site.ts";

const html = document.documentElement;

// Tema: varsayılan aydınlık; üst bardaki düğme koyu/aydınlık arasında geçer (localStorage "gituar-theme")
const themeBtn = document.getElementById("theme-toggle");
const themeMeta = document.getElementById("theme-color");
function isDark(): boolean { return html.getAttribute("data-theme") === "dark"; }
function syncThemeLabel() {
  const label = isDark() ? "Aydınlık tema" : "Koyu tema";
  themeBtn?.setAttribute("aria-label", label);
  themeBtn?.setAttribute("title", label);
  themeMeta?.setAttribute("content", isDark() ? "#000000" : "#f5f5f7");
  const footerLabel = document.querySelector("#theme-toggle-footer span");
  if (footerLabel) footerLabel.textContent = isDark() ? "Gündüz modu" : "Gece modu";
}
function toggleTheme() {
  const next = isDark() ? "light" : "dark";
  html.setAttribute("data-theme", next);
  try { localStorage.setItem("gituar-theme", next); } catch {}
  syncThemeLabel();
}
themeBtn?.addEventListener("click", toggleTheme);
document.getElementById("theme-toggle-footer")?.addEventListener("click", toggleTheme);
document.getElementById("theme-toggle-home")?.addEventListener("click", toggleTheme);
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

// "/" ve ⌘K arama panelini açar (palette.ts)

// Giriş durumu → üst bar; Plus durumu → reklamlar
let adsLoaded = false;
const authBtns = [document.getElementById("auth-btn"), document.getElementById("auth-btn-mobile")].filter(Boolean) as HTMLAnchorElement[];
// Daha önce giriş yapmamış ziyaretçide Firebase SDK hiç indirilmez (sayfa hızı).
let hadSession = false;
try { hadSession = localStorage.getItem("gituar-auth") === "1"; } catch {}
if (firebaseReady && hadSession) {
  onUser((user) => {
    for (const btn of authBtns) {
      btn.textContent = user ? "Hesabım" : "Giriş yap";
      btn.href = user ? "/hesap/" : "/giris/";
    }
    setHeaderUser(user ? { n: user.displayName || user.email || "", p: user.photoURL || "" } : null);
    if (user) refreshPlus(user.uid).then((plus) => { if (!plus) loadAds(); });
    else loadAds();
    // Yönetim bağlantısı yalnızca admin hesaplarda (users/{uid}.isAdmin)
    // Sayfa açılışında son bilinen durum (gituar-admin) <html class="is-admin"> olarak zaten konmuştur; burada yalnızca doğrulanır.
    if (user) isAdminUser(user.uid).then((admin) => html.classList.toggle("is-admin", admin));
    else html.classList.remove("is-admin");
  });
} else {
  loadAds();
}

/** Üst bardaki profil resmi / baş harf; bilgi bir sonraki sayfa açılışı için saklanır (Header.astro'daki satır içi betik okur). */
function setHeaderUser(u: { n: string; p: string } | null) {
  html.classList.toggle("signed-in", Boolean(u));
  try { u ? localStorage.setItem("gituar-user", JSON.stringify(u)) : localStorage.removeItem("gituar-user"); } catch {}
  const initial = document.getElementById("header-avatar-initial");
  const img = document.getElementById("header-avatar-img") as HTMLImageElement | null;
  if (!u || !initial || !img) return;
  initial.textContent = (u.n.trim()[0] ?? "?").toLocaleUpperCase("tr-TR");
  if (u.p) { if (img.getAttribute("src") !== u.p) img.src = u.p; img.hidden = false; }
  else { img.hidden = true; img.removeAttribute("src"); }
}
// Fotoğraf yüklenemezse baş harf kalır
document.getElementById("header-avatar-img")?.addEventListener("error", (e) => { (e.target as HTMLImageElement).hidden = true; });

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

// Hesap silindikten sonra ana sayfada bilgi
if (new URLSearchParams(location.search).get("hesap") === "silindi") {
  const note = document.createElement("div");
  note.className = "alert";
  note.textContent = "Hesabın ve bütün verilerin silindi.";
  document.querySelector("main")?.prepend(note);
  history.replaceState(null, "", location.pathname);
}

// Açılır bölümlerdeki "Tümü" satırı (listede en az 19 öğe varsa) listenin son hücresi olur. İki sütunda (sütunlar önce aşağı dolar)
// hücre sayısı tekse son satırda yalnızca sol hücre kalır; "Tümü" oraya, sol alt köşeye yerleşir.
// Liste sonradan doldurulsa da (repertuarlar, rastgele) ve ekran genişliği değişse de yeri korunur.
const twoCols = matchMedia("(min-width: 728px)");
const MIN_FOR_ALL = 19;
function placeAllRows() {
  document.querySelectorAll<HTMLElement>(".rp-all-holder").forEach((holder) => {
    const item = holder.querySelector<HTMLElement>(".rp-all-item");
    const list = holder.parentElement?.querySelector<HTMLElement>(".rp-list:not(.rp-all-holder)");
    if (!item || !list) return;
    holder.remove();
    const place = () => {
      const others = [...list.children].filter((el) => el !== item && !(el as HTMLElement).hidden);
      // Liste en az 19 öğe (şarkı, sanatçı, repertuar) değilse "Tümü" gösterilmez
      item.hidden = others.length < MIN_FOR_ALL;
      if (item.hidden) return;
      const total = others.length + 1;
      // Sol sütunun sonu: ilk ceil(total/2) hücre sol sütundadır
      const index = twoCols.matches && total % 2 === 1 ? Math.ceil(total / 2) - 1 : others.length;
      const before = others[index] ?? null;
      if (item.nextElementSibling !== before || item.parentElement !== list) list.insertBefore(item, before);
    };
    place();
    new MutationObserver(place).observe(list, { childList: true });
    twoCols.addEventListener("change", place);
  });
}
placeAllRows();
