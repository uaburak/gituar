// Şarkıyı ritim ya da arpejle çalar: kâğıttaki akorlar sırayla, her akor bir ölçü.
// Ses zamanlaması Web Audio saatine göre önceden planlanır (kaymaz); çalan akor ve vuruş ekranda işaretlenir.
// Ritim/arpej/tempo şarkıda yoksa yaygın bir desen kullanılır. Ton ve kapo hesaba katılır.
import { simplifyChord, chordShapes } from "../lib/chord-theory.ts";
import { parseRhythm, parseArpeggio, beatsPerBar, tempoLabel, DEFAULT_TEMPO, type Stroke, type Pluck } from "../lib/rhythm.ts";

type Audio = typeof import("../lib/chord-audio.ts");
type Prepared = import("../lib/chord-audio.ts").PreparedChord;

const song = document.getElementById("song");
const pre = document.getElementById("chords");
const playBtn = document.getElementById("rh-play") as HTMLButtonElement | null;
const patternEl = document.getElementById("rh-pattern");
const tempoInput = document.getElementById("rh-tempo") as HTMLInputElement | null;
const tempoVal = document.getElementById("rh-tempo-val");
const note = document.getElementById("rh-note");
const modeBtns = [...document.querySelectorAll<HTMLButtonElement>(".rh-mode button")];

if (song && pre && playBtn && patternEl && tempoInput && tempoVal) {
  const d = song.dataset;
  const rhythm = parseRhythm(d.rhythm);
  const arpeggio = parseArpeggio(d.arpeggio);
  const beats = beatsPerBar(d.meter);
  let mode: "rhythm" | "arpeggio" = !d.rhythm && d.arpeggio ? "arpeggio" : "rhythm";
  let tempo = Number(d.tempo) || DEFAULT_TEMPO;
  if (!d.rhythm && !d.arpeggio && note) note.textContent = "Bu şarkıya ritim eklenmemiş; en yaygın ritimle çalınır. Her akor bir ölçü çalınır.";

  const slots = () => (mode === "rhythm" ? rhythm : arpeggio);
  const label = (x: Stroke | Pluck) => (mode === "rhythm" ? (x === "down" ? "↓" : x === "up" ? "↑" : "·") : x === "bass" ? "B" : x === null ? "·" : String(6 - (x as number)));

  function renderPattern() {
    patternEl!.innerHTML = slots().map((x) => `<span class="rh-slot${x === null ? " is-rest" : ""}">${label(x)}</span>`).join("");
    for (const b of modeBtns) b.setAttribute("aria-pressed", String(b.dataset.mode === mode));
  }
  function renderTempo() {
    tempoInput!.value = String(tempo);
    tempoVal!.textContent = `${tempo} BPM · ${tempoLabel(tempo)}`;
  }
  renderPattern();
  renderTempo();
  for (const b of modeBtns) b.addEventListener("click", () => { mode = b.dataset.mode as typeof mode; renderPattern(); });
  tempoInput.addEventListener("input", () => { tempo = Number(tempoInput.value); renderTempo(); });

  // ---- Çalma ----
  let audioMod: Audio | null = null;
  const prepared = new Map<string, Promise<Prepared | null>>();
  let timer = 0;
  let playing = false;
  let nextTime = 0, bar = 0, slot = 0;
  let current: HTMLElement | null = null;

  const capo = () => Number(document.getElementById("capo-val")?.textContent ?? 0) || 0;
  const chordEls = () => [...pre.querySelectorAll<HTMLElement>(".chord")];

  function prep(name: string): Promise<Prepared | null> {
    const key = `${name}|${capo()}`;
    if (!prepared.has(key)) {
      const c = simplifyChord(name);
      const shape = c ? chordShapes(c.root, c.quality)[0] : undefined;
      prepared.set(key, shape ? audioMod!.prepare(shape.frets, capo()) : Promise.resolve(null));
    }
    return prepared.get(key)!;
  }
  const ready = new Map<string, Prepared | null>();
  async function prepAll() {
    const names = [...new Set(chordEls().map((el) => el.textContent ?? ""))];
    await Promise.all(names.map(async (n) => ready.set(`${n}|${capo()}`, await prep(n))));
  }

  function mark(el: HTMLElement | null, slotIndex: number) {
    if (el !== current) {
      current?.classList.remove("is-now");
      el?.classList.add("is-now");
      current = el;
      if (el) {
        const r = el.getBoundingClientRect();
        if (r.top < innerHeight * 0.25 || r.bottom > innerHeight * 0.7) el.scrollIntoView({ block: "center", behavior: "smooth" });
      }
    }
    patternEl!.querySelectorAll(".rh-slot").forEach((s, i) => s.classList.toggle("is-now", i === slotIndex));
  }

  function schedule() {
    const ac = audioMod!.audio();
    const list = chordEls();
    while (playing && nextTime < ac.currentTime + 0.15) {
      if (bar >= list.length) { stop(); return; }
      const el = list[bar];
      const chord = ready.get(`${el.textContent ?? ""}|${capo()}`);
      if (chord === undefined) void prep(el.textContent ?? "").then((p) => ready.set(`${el.textContent ?? ""}|${capo()}`, p)); // ton/kapo değiştiyse sonraki ölçüye hazır
      const pattern = slots();
      const x = pattern[slot];
      const onBeat = (slot * beats) % pattern.length === 0;
      if (chord && x !== null && x !== undefined) {
        if (mode === "rhythm") audioMod!.strumAt(chord, nextTime, x as Stroke & string, onBeat ? 0.55 : 0.42);
        else audioMod!.pluckAt(chord, x as number | "bass", nextTime, onBeat ? 0.6 : 0.48);
      }
      const at = nextTime, s = slot;
      setTimeout(() => { if (playing) mark(el, s); }, Math.max(0, (at - ac.currentTime) * 1000));
      nextTime += (beats * 60) / tempo / pattern.length;
      slot++;
      if (slot >= pattern.length) { slot = 0; bar++; }
    }
  }

  async function start() {
    if (!chordEls().length) { if (note) note.textContent = "Bu şarkıda çalınacak akor yok."; return; }
    playBtn!.disabled = true;
    audioMod ??= await import("../lib/chord-audio.ts");
    const ac = audioMod.audio();
    await prepAll();
    playing = true;
    // Ekranda görünen akordan başla (kullanıcı kâğıdın ortasındaysa oradan devam)
    const list = chordEls();
    const firstVisible = list.findIndex((el) => el.getBoundingClientRect().top > 80);
    bar = firstVisible > 0 && list[firstVisible].getBoundingClientRect().top < innerHeight ? firstVisible : 0;
    slot = 0;
    nextTime = ac.currentTime + 0.12;
    playBtn!.disabled = false;
    playBtn!.setAttribute("aria-pressed", "true");
    playBtn!.querySelector("span")!.textContent = "Durdur";
    schedule();
    timer = window.setInterval(schedule, 25);
  }
  function stop() {
    playing = false;
    clearInterval(timer);
    audioMod?.silence();
    mark(null, -1);
    playBtn!.setAttribute("aria-pressed", "false");
    playBtn!.querySelector("span")!.textContent = "Çal";
  }
  playBtn.addEventListener("click", () => (playing ? stop() : void start()));
  document.addEventListener("visibilitychange", () => { if (document.hidden && playing) stop(); });
}
