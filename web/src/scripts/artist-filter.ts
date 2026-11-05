// Sanatçılar: ad filtresi, harf şeridinde yumuşak kaydırma, yapışan şerit ve ekrandaki gruba göre aktif harf.
import { turkeyNormalized } from "@shared/turkish";

const input = document.getElementById("artist-filter") as HTMLInputElement;
const rows = [...document.querySelectorAll<HTMLAnchorElement>("[data-group] .artist-row")].map((el) => ({ el, key: turkeyNormalized(el.textContent ?? "") }));
const groups = [...document.querySelectorAll<HTMLElement>("[data-group]")];
const rail = document.querySelector<HTMLElement>(".letters");
const letterLinks = [...document.querySelectorAll<HTMLAnchorElement>(".letters a[data-letter]")];
const empty = document.getElementById("filter-empty");
const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;

input.addEventListener("input", () => {
  const q = turkeyNormalized(input.value.trim());
  let visible = 0;
  for (const r of rows) { const show = !q || r.key.includes(q); r.el.hidden = !show; if (show) visible++; }
  for (const g of groups) g.hidden = Boolean(q) && !g.querySelector(".artist-row:not([hidden])");
  if (rail) rail.hidden = Boolean(q);
  if (empty) empty.hidden = visible > 0;
});

// ---- Yumuşak kaydırma (kendi animasyonumuz: tarayıcının native smooth'u uzun mesafede çok yavaş/tutarsız) ----
let scrollAnim = 0;
let animating = false;
const easeInOutCubic = (t: number) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);

function smoothScrollTo(targetY: number) {
  cancelAnimationFrame(scrollAnim);
  const max = document.documentElement.scrollHeight - innerHeight;
  const endY = Math.max(0, Math.min(targetY, max));
  if (reduceMotion) { window.scrollTo({ top: endY, behavior: "instant" }); return; }
  const startY = scrollY;
  const distance = endY - startY;
  const duration = Math.min(800, 350 + Math.abs(distance) * 0.01); // 350–800 ms, mesafeye göre
  const t0 = performance.now();
  animating = true;
  const step = (now: number) => {
    const t = Math.min(1, (now - t0) / duration);
    window.scrollTo({ top: startY + distance * easeInOutCubic(t), behavior: "instant" });
    updateStuck();
    if (t < 1) scrollAnim = requestAnimationFrame(step);
    else { animating = false; updateActive(); }
  };
  scrollAnim = requestAnimationFrame(step);
}
const cancelScroll = () => { if (animating) { cancelAnimationFrame(scrollAnim); animating = false; } };
window.addEventListener("wheel", cancelScroll, { passive: true });
window.addEventListener("touchstart", cancelScroll, { passive: true });
window.addEventListener("keydown", cancelScroll);

// Grubun üstü: header + şerit + 8px boşluk
function groupOffset() {
  if (!rail) return 96;
  return (parseFloat(getComputedStyle(rail).top) || 84) + rail.offsetHeight + 8;
}

for (const link of letterLinks) {
  link.addEventListener("click", (e) => {
    const target = document.getElementById(link.dataset.letter!);
    if (!target) return;
    e.preventDefault();
    setActive(link.dataset.letter!);
    smoothScrollTo(target.getBoundingClientRect().top + scrollY - groupOffset());
    history.replaceState(null, "", `#${link.dataset.letter}`);
  });
}

// Aktif harfi işaretler; dar ekranda şerit taşıyorsa harfi ortaya kaydırır.
// (Harf için scrollIntoView kullanılmaz: sayfanın süren kaydırmasını iptal ediyordu.)
function setActive(id: string) {
  for (const link of letterLinks) {
    const on = link.dataset.letter === id;
    link.classList.toggle("active", on);
    if (on && rail && rail.scrollWidth > rail.clientWidth) {
      const left = link.offsetLeft - (rail.clientWidth - link.offsetWidth) / 2;
      rail.scrollTo({ left, behavior: reduceMotion ? "instant" : "smooth" });
    }
  }
}

// Ekranın üst bölgesindeki grup → aktif harf (animasyon sürerken tıklanan harf korunur)
function updateActive() {
  if (animating || !rail) return;
  const line = groupOffset() + 80;
  let current: HTMLElement | null = null;
  for (const g of groups) {
    if (g.hidden) continue;
    if (g.getBoundingClientRect().top <= line) current = g; else break;
  }
  if (current) setActive(current.id);
}

// Şerit header'ın altına yapıştığında beyaz zemin + gölge (.stuck)
function updateStuck() {
  if (!rail) return;
  const top = parseFloat(getComputedStyle(rail).top) || 0;
  rail.classList.toggle("stuck", rail.getBoundingClientRect().top <= top + 0.5);
}

let ticking = false;
window.addEventListener("scroll", () => {
  if (ticking) return;
  ticking = true;
  requestAnimationFrame(() => { updateActive(); updateStuck(); ticking = false; });
}, { passive: true });
updateActive();
updateStuck();
