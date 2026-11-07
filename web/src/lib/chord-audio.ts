// Akor sesi: akustik gitar nota kayıtlarıyla (public/sounds/guitar, CC BY 3.0) teller aşağıdan yukarı tınlatılır.
// Standart akort; perde → MIDI nota. Kayıt olmayan üst notalar en yakın kaydın hızı değiştirilerek çalınır.
const OPEN = [40, 45, 50, 55, 59, 64]; // E2 A2 D3 G3 B3 E4
const NAMES = ["C", "Cs", "D", "Ds", "E", "F", "Fs", "G", "Gs", "A", "As", "B"];
const MIN = 40, MAX = 74; // E2 … D5 kayıtlı
const STRUM = 0.035; // teller arası saniye

let ctx: AudioContext | null = null;
const buffers = new Map<number, Promise<AudioBuffer>>();
let active: { src: AudioBufferSourceNode; gain: GainNode }[] = [];

function audio(): AudioContext {
  if (!ctx) ctx = new (window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext)();
  if (ctx.state === "suspended") void ctx.resume();
  return ctx;
}

function sample(midi: number): Promise<AudioBuffer> {
  if (!buffers.has(midi)) {
    const name = NAMES[midi % 12] + (Math.floor(midi / 12) - 1);
    buffers.set(midi, fetch(`/sounds/guitar/${name}.m4a`).then((r) => r.arrayBuffer()).then((b) => audio().decodeAudioData(b)));
  }
  return buffers.get(midi)!;
}

/** Perdeler: 6 tel (kalın E'den ince E'ye), -1 çalınmaz, 0 açık tel. `capo` perdesi hepsine eklenir. */
export async function playFrets(frets: number[], capo = 0): Promise<void> {
  const ac = audio();
  // Önceki akoru kısa bir kısılmayla sustur
  const now = ac.currentTime;
  for (const a of active) { a.gain.gain.setTargetAtTime(0, now, 0.03); a.src.stop(now + 0.2); }
  active = [];
  const notes = frets.map((f, s) => (f < 0 ? -1 : OPEN[s] + f + capo)).filter((m) => m >= MIN - 12);
  const loaded = await Promise.all(notes.map((m) => (m < 0 ? null : sample(Math.min(Math.max(m, MIN), MAX)))));
  const start = ac.currentTime + 0.02;
  let i = 0;
  notes.forEach((m, k) => {
    const buf = loaded[k];
    if (m < 0 || !buf) return;
    const src = ac.createBufferSource();
    src.buffer = buf;
    const base = Math.min(Math.max(m, MIN), MAX);
    src.playbackRate.value = Math.pow(2, (m - base) / 12);
    const gain = ac.createGain();
    gain.gain.value = 0.55;
    src.connect(gain).connect(ac.destination);
    src.start(start + i * STRUM);
    i++;
    active.push({ src, gain });
  });
}
