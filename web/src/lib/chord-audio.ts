// Akor sesi: akustik gitar nota kayıtlarıyla (public/sounds/guitar, CC BY 3.0).
// İki kullanım: tek akoru tınlatmak (playFrets) ve şarkıyı ritim/arpejle çalarken zamanlanmış vuruşlar (prepare + strumAt/pluckAt).
// Standart akort; perde → MIDI nota. Kayıt olmayan üst notalar en yakın kaydın hızı değiştirilerek çalınır.
const OPEN = [40, 45, 50, 55, 59, 64]; // E2 A2 D3 G3 B3 E4 (0 = kalın E … 5 = ince E)
const NAMES = ["C", "Cs", "D", "Ds", "E", "F", "Fs", "G", "Gs", "A", "As", "B"];
const MIN = 40, MAX = 74; // E2 … D5 kayıtlı

let ctx: AudioContext | null = null;
const buffers = new Map<number, Promise<AudioBuffer>>();
type Voice = { src: AudioBufferSourceNode; gain: GainNode };
const ringing: (Voice | null)[] = [null, null, null, null, null, null];

export function audio(): AudioContext {
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

/** Hazırlanmış akor: her tel için kayıt ve hız (çalınmayan tel null). */
export type PreparedChord = ({ buf: AudioBuffer; rate: number } | null)[];

/** Perdeler: 6 tel (kalın E'den ince E'ye), -1 çalınmaz, 0 açık tel. `capo` perdesi hepsine eklenir. */
export async function prepare(frets: number[], capo = 0): Promise<PreparedChord> {
  return Promise.all(frets.map(async (f, s) => {
    if (f < 0) return null;
    const m = OPEN[s] + f + capo;
    const base = Math.min(Math.max(m, MIN), MAX);
    return { buf: await sample(base), rate: Math.pow(2, (m - base) / 12) };
  }));
}

/** Teli `t` anında tınlatır; aynı teldeki önceki ses kısa bir kısılmayla susar (gerçek gitardaki gibi). */
function noteAt(string: number, p: PreparedChord[number], t: number, vel: number) {
  const ac = audio();
  const prev = ringing[string];
  if (prev) { prev.gain.gain.setTargetAtTime(0, t, 0.015); prev.src.stop(t + 0.2); }
  ringing[string] = null;
  if (!p) return;
  const src = ac.createBufferSource();
  src.buffer = p.buf;
  src.playbackRate.value = p.rate;
  const gain = ac.createGain();
  gain.gain.value = vel;
  src.connect(gain).connect(ac.destination);
  src.start(t);
  ringing[string] = { src, gain };
}

/** Vuruş: aşağı = kalın telden inceye, yukarı = inceden kalına ve yalnızca ince dört tel. */
export function strumAt(chord: PreparedChord, t: number, dir: "down" | "up", vel = 0.5, spread = 0.012) {
  const order = dir === "down" ? [0, 1, 2, 3, 4, 5] : [5, 4, 3, 2];
  let i = 0;
  for (const s of order) {
    if (!chord[s]) continue;
    noteAt(s, chord[s], t + i * spread, dir === "down" ? vel : vel * 0.75);
    i++;
  }
}

/** Kesme vuruşu ("K"): teller susturulmuş, kısa ve boğuk bir "tık"; çalan tellerin sesini de keser. */
export function muteAt(chord: PreparedChord, t: number, vel = 0.35) {
  const ac = audio();
  let i = 0;
  for (let s = 0; s < 6; s++) {
    const prev = ringing[s];
    if (prev) { prev.gain.gain.setTargetAtTime(0, t, 0.008); prev.src.stop(t + 0.1); ringing[s] = null; }
    const p = chord[s];
    if (!p || s < 1) continue;
    const src = ac.createBufferSource();
    src.buffer = p.buf;
    src.playbackRate.value = p.rate;
    const gain = ac.createGain();
    gain.gain.setValueAtTime(vel, t + i * 0.006);
    gain.gain.setTargetAtTime(0, t + i * 0.006 + 0.02, 0.012);
    src.connect(gain).connect(ac.destination);
    src.start(t + i * 0.006);
    src.stop(t + i * 0.006 + 0.12);
    i++;
  }
}

/** Arpej notası: `string` 0 (kalın E) … 5 (ince E); "bas" için çalınan en kalın tel. */
export function pluckAt(chord: PreparedChord, string: number | "bass", t: number, vel = 0.5) {
  const s = string === "bass" ? chord.findIndex((x) => x) : string;
  if (s < 0 || !chord[s]) return;
  noteAt(s, chord[s], t, vel);
}

/** Bütün telleri susturur. */
export function silence() {
  const t = audio().currentTime;
  for (let s = 0; s < 6; s++) noteAt(s, null, t, 0);
}

/** Tek akoru bir aşağı vuruşla tınlatır (diyagram ve kâğıttaki akora tıklama). */
export async function playFrets(frets: number[], capo = 0): Promise<void> {
  const chord = await prepare(frets, capo);
  strumAt(chord, audio().currentTime + 0.02, "down", 0.55, 0.035);
}
