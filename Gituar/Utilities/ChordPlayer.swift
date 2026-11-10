import AVFoundation

// MARK: - ChordPlayer
//
// Kâğıttaki akora dokununca akoru bir aşağı vuruşla tınlatır (web/src/lib/chord-audio.ts'in karşılığı).
// Akustik gitar nota kayıtları (Resources/GuitarSounds, E2–D5, CC BY 3.0) her tel için ayrı bir oynatıcıda çalınır;
// kayıt aralığı dışındaki notalar en yakın kaydın hızı değiştirilerek (varispeed) elde edilir.

@MainActor
final class ChordPlayer {
    static let shared = ChordPlayer()

    private static let openStrings = [40, 45, 50, 55, 59, 64] // E2 A2 D3 G3 B3 E4
    private static let names = ["C", "Cs", "D", "Ds", "E", "F", "Fs", "G", "Gs", "A", "As", "B"]
    private static let minMidi = 40, maxMidi = 74

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var speeds: [AVAudioUnitVarispeed] = []
    private var buffers: [Int: AVAudioPCMBuffer] = [:]
    private var isSetUp = false
    private var isConnected = false

    private init() {}

    private func setUp() {
        guard !isSetUp else { return }
        isSetUp = true
        for _ in 0..<6 {
            let player = AVAudioPlayerNode()
            let speed = AVAudioUnitVarispeed()
            engine.attach(player)
            engine.attach(speed)
            players.append(player)
            speeds.append(speed)
        }
    }

    private func buffer(midi: Int) -> AVAudioPCMBuffer? {
        if let b = buffers[midi] { return b }
        let name = Self.names[midi % 12] + String(midi / 12 - 1)
        guard let url = Bundle.main.url(forResource: name, withExtension: "m4a"),
              let file = try? AVAudioFile(forReading: url),
              let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buf)) != nil else { return nil }
        buffers[midi] = buf
        return buf
    }

    /// Perdeler: 6 tel (kalın E'den ince E'ye), -1 çalınmaz. `capo` perdesi hepsine eklenir.
    func play(frets: [Int], capo: Int = 0) {
        setUp()
        // Sessiz anahtarda da duyulsun (kısa bir akor önizlemesi; başka sesleri kesmez)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        var notes: [(string: Int, buf: AVAudioPCMBuffer, rate: Float)] = []
        for (s, f) in frets.enumerated() where s < 6 && f >= 0 {
            let midi = Self.openStrings[s] + f + capo
            let base = min(max(midi, Self.minMidi), Self.maxMidi)
            guard let buf = buffer(midi: base) else { continue }
            notes.append((s, buf, powf(2, Float(midi - base) / 12)))
        }
        guard let format = notes.first?.buf.format else { return }

        // Bağlantılar örnek biçimiyle bir kez kurulur
        if !isConnected {
            for s in 0..<6 {
                engine.connect(players[s], to: speeds[s], format: format)
                engine.connect(speeds[s], to: engine.mainMixerNode, format: format)
            }
            isConnected = true
        }
        if !engine.isRunning {
            do { try engine.start() } catch { print("⚠️ ChordPlayer: \(error.localizedDescription)"); return }
        }

        let start = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.03)
        for (i, note) in notes.enumerated() {
            let player = players[note.string]
            player.stop()
            speeds[note.string].rate = note.rate
            player.volume = 0.6
            // Aşağı vuruş: kalın telden inceye, teller arası 35 ms
            let when = AVAudioTime(hostTime: start + AVAudioTime.hostTime(forSeconds: Double(i) * 0.035))
            player.scheduleBuffer(note.buf, at: nil, options: [.interrupts])
            player.play(at: when)
        }
        #if DEBUG
        print("🎸 ChordPlayer: \(notes.count) tel çalındı (perdeler \(frets), kapo \(capo))")
        #endif
        // Çalmayan teller susar
        let playing = Set(notes.map(\.string))
        for s in 0..<6 where !playing.contains(s) { players[s].stop() }
    }
}
