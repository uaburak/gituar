// Her sayfada çalışır: gece modu, mobil menü, giriş durumu, Pro bayrağı, reklam yükleme.
import { firebaseReady, onUser, refreshPro, isAdminUser } from "../lib/firebase-client.ts";
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

// Giriş durumu → üst bar; Pro durumu → reklamlar
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
    if (user) refreshPro(user.uid).then((pro) => { if (!pro) loadAds(); });
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
  if (adsLoaded || !ADSENSE_CLIENT || html.classList.contains("pro")) return;
  adsLoaded = true;
  const s = document.createElement("script");
  s.async = true;
  s.crossOrigin = "anonymous";
  s.src = `https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=${ADSENSE_CLIENT}`;
  // KVKK: açık rıza ("all") yoksa reklam istekleri kişiselleştirilmemiş gider. Betik yüklenmeden önce kuyruğa konmalı.
  const q = ((window as unknown as { adsbygoogle?: AdsQueue }).adsbygoogle ??= [] as unknown as AdsQueue);
  q.requestNonPersonalizedAds = consentChoice() === "all" ? 0 : 1;
  s.onload = fillAds;
  document.head.appendChild(s);
  // Yan reklamlar yalnızca ≥1440 px'te görünür; pencere sonradan genişlerse o yerler de doldurulur
  matchMedia("(min-width: 1440px)").addEventListener("change", () => { if (adsLoaded) fillAds(); });
}

type AdsQueue = unknown[] & { requestNonPersonalizedAds?: 0 | 1 };
function consentChoice(): string | null {
  try { return localStorage.getItem("gituar-consent"); } catch { return null; }
}
// Kabul edilince sonraki reklam istekleri (geçiş reklamı, yeni sayfa) kişiselleştirilebilir; reddedilince kişiselleştirilmemiş kalır
document.addEventListener("gituar:consent", (e) => {
  const q = (window as unknown as { adsbygoogle?: AdsQueue }).adsbygoogle;
  if (q) q.requestNonPersonalizedAds = (e as CustomEvent<string>).detail === "all" ? 0 : 1;
});
// Alt bilgideki "Çerez tercihleri": izni geri almak ya da değiştirmek için bildirimi yeniden açar (KVKK)
document.getElementById("consent-reopen")?.addEventListener("click", () => {
  const box = document.getElementById("consent");
  if (!box) return;
  box.hidden = false;
  document.getElementById("consent-accept")?.focus();
});

// AdSense otomatik reklamlarının alt şeridi (anchor) ekranın altına yapışır; çerez bildirimi ve oynat çubuğu onun altında
// kalmasın diye şeridin yüksekliği --anchor-h olarak yazılır (global.css bu kadar yukarı kaydırır). Şerit kapanınca 0 olur.
function watchAnchorAd() {
  let current: HTMLElement | null = null;
  const measure = () => {
    let h = 0;
    if (current && current.isConnected) {
      const r = current.getBoundingClientRect();
      if (r.height > 0 && r.top < innerHeight && r.bottom >= innerHeight - 2) h = Math.round(innerHeight - r.top);
    }
    html.style.setProperty("--anchor-h", `${h}px`);
  };
  const ro = new ResizeObserver(measure);
  const attrs = new MutationObserver(measure);
  const find = () => {
    const el = [...document.querySelectorAll<HTMLElement>("body > ins.adsbygoogle, html > ins.adsbygoogle")]
      .find((x) => getComputedStyle(x).position === "fixed" && x.getBoundingClientRect().bottom >= innerHeight - 2 && x.getBoundingClientRect().width > innerWidth / 2);
    if (el && el !== current) {
      current = el;
      ro.disconnect(); attrs.disconnect();
      ro.observe(el);
      attrs.observe(el, { attributes: true, attributeFilter: ["style", "data-anchor-status"] });
    }
    measure();
  };
  new MutationObserver(find).observe(document.body, { childList: true });
  new MutationObserver(find).observe(html, { childList: true });
  addEventListener("resize", measure);
}
watchAnchorAd();

/** Görünür ve henüz işlenmemiş her <ins> için bir push. Gizli yerler (dar ekranda yan reklamlar) için de push yapılırsa
 *  AdSense konsola "All 'ins' elements ... already have ads in them" hatası basar (PageSpeed "En İyi Uygulamalar" düşer). */
function fillAds() {
  const w = window as unknown as { adsbygoogle?: unknown[] };
  document.querySelectorAll<HTMLElement>("ins.adsbygoogle").forEach((el) => {
    if (el.dataset.adsbygoogleStatus || el.getClientRects().length === 0) return;
    (w.adsbygoogle = w.adsbygoogle || []).push({});
  });
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

// Akor diyagramına tıklayınca akor sesi (ses kodu ve kayıtlar yalnızca ilk tıklamada yüklenir)
document.addEventListener("click", (e) => {
  const btn = (e.target as HTMLElement).closest<HTMLElement>("[data-frets]");
  if (!btn) return;
  const frets = (btn.dataset.frets ?? "").split(",").map(Number);
  btn.classList.add("cd-playing");
  setTimeout(() => btn.classList.remove("cd-playing"), 600);
  void import("../lib/chord-audio.ts").then((m) => m.playFrets(frets));
});
