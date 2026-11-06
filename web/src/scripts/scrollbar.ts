// Masaüstünde (fare/trackpad) sayfanın kendi kaydırma çubuğu gizlenir, yerine içeriğin üstünde yüzen ince bir çubuk çizilir.
// Böylece kaydırma çubuğu belirdiğinde sayfa sola kaymaz. Tekerlek, klavye ve dokunmatik kaydırma tarayıcıda kalır.
const fine = window.matchMedia("(pointer: fine)");
if (fine.matches) init();

function init() {
  const root = document.documentElement;
  root.classList.add("overlay-scroll");
  const track = document.createElement("div");
  track.className = "vscroll";
  track.setAttribute("aria-hidden", "true");
  const thumb = document.createElement("div");
  thumb.className = "vscroll-thumb";
  track.appendChild(thumb);
  document.body.appendChild(track);

  let hideTimer = 0;
  let dragging = false;
  let dragStartY = 0;
  let dragStartScroll = 0;
  let thumbH = 0;

  function metrics() {
    const vh = window.innerHeight;
    const docH = root.scrollHeight;
    return { vh, docH, max: Math.max(0, docH - vh) };
  }
  function update() {
    const { vh, docH, max } = metrics();
    if (max <= 0) { track.hidden = true; return; }
    track.hidden = false;
    thumbH = Math.max(36, (vh * vh) / docH);
    const top = (window.scrollY / max) * (vh - thumbH);
    thumb.style.height = `${thumbH}px`;
    thumb.style.transform = `translateY(${top}px)`;
  }
  function show() {
    track.classList.add("active");
    window.clearTimeout(hideTimer);
    hideTimer = window.setTimeout(() => { if (!dragging) track.classList.remove("active"); }, 900);
  }

  window.addEventListener("scroll", () => { update(); show(); }, { passive: true });
  window.addEventListener("resize", update);
  new ResizeObserver(update).observe(document.body);
  // Sağ kenara yaklaşınca çubuk görünür
  window.addEventListener("mousemove", (e) => { if (window.innerWidth - e.clientX < 18) show(); }, { passive: true });

  thumb.addEventListener("pointerdown", (e) => {
    dragging = true;
    dragStartY = e.clientY;
    dragStartScroll = window.scrollY;
    thumb.setPointerCapture(e.pointerId);
    track.classList.add("active", "dragging");
    e.preventDefault();
  });
  thumb.addEventListener("pointermove", (e) => {
    if (!dragging) return;
    const { vh, max } = metrics();
    const ratio = max / Math.max(1, vh - thumbH);
    window.scrollTo({ top: dragStartScroll + (e.clientY - dragStartY) * ratio, behavior: "instant" });
  });
  const end = () => { dragging = false; track.classList.remove("dragging"); show(); };
  thumb.addEventListener("pointerup", end);
  thumb.addEventListener("pointercancel", end);
  // Boş ize tıklayınca o noktaya git
  track.addEventListener("pointerdown", (e) => {
    if (e.target !== track) return;
    const { vh, max } = metrics();
    window.scrollTo({ top: (e.clientY / vh) * max - vh / 2, behavior: "smooth" });
  });
  update();
}
