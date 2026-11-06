// ⌘K / Ctrl+K / "/": her sayfadan arama sayfasına gider; arama sayfasındaysa kutuya odaklanır.
const kbd = document.getElementById("search-kbd");
if (kbd) kbd.textContent = /Mac|iPhone|iPad/.test(navigator.platform) ? "⌘K" : "Ctrl K";

function goSearch() {
  const box = document.getElementById("q") as HTMLInputElement | null;
  if (box && location.pathname === "/ara/") { box.focus(); box.select(); return; }
  location.href = "/ara/";
}

document.addEventListener("keydown", (e) => {
  const t = e.target as HTMLElement | null;
  const typing = t && (/^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName) || t.isContentEditable);
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") { e.preventDefault(); goSearch(); return; }
  if (e.key === "/" && !typing && !e.metaKey && !e.ctrlKey && !e.altKey) { e.preventDefault(); goSearch(); }
});
