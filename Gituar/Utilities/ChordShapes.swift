import Foundation

// MARK: - ChordShapes
//
// Web'deki akor kuramının (web/src/lib/chord-theory.ts) Swift karşılığı: akor adını sadeleştirme ve
// gitar tutuşları (açık akor tablosu + E/A biçimli barre). Kâğıttaki akora dokununca diyagram ve ses bunu kullanır.

nonisolated enum ChordShapes {

    /// Telden tele (6. kalın tel → 1. ince tel) perde; -1 çalınmaz, 0 açık tel.
    struct Shape: Hashable, Sendable {
        let frets: [Int]
        let barre: Int?
        let name: String
    }

    private static let sharps = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private static let flats = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
    private static let pc: [String: Int] = [
        "C": 0, "B#": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "Fb": 4, "F": 5, "E#": 5,
        "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11, "Cb": 11,
    ]

    /// Desteklenen nitelikler (web ile aynı).
    private static let qualities: Set<String> = ["", "m", "7", "m7", "maj7", "sus2", "sus4", "7sus4", "dim", "m7b5", "aug", "6", "m6", "add9", "9"]

    private static let qualityMap: [String: String] = [
        "min": "m", "mi": "m", "-": "m", "maj": "", "M": "", "M7": "maj7", "Maj7": "maj7", "ma7": "maj7", "min7": "m7",
        "m7(b5)": "m7b5", "ø": "m7b5", "ø7": "m7b5", "°": "dim", "dim7": "dim", "°7": "dim", "+": "aug", "sus": "sus4",
        "7sus": "7sus4", "add2": "add9", "2": "sus2", "4": "sus4", "min6": "m6", "maj9": "maj7", "m9": "m7", "madd9": "m",
        "6/9": "6", "5": "",
    ]

    private static let open: [String: String] = [
        "C": "x32010", "D": "xx0232", "E": "022100", "G": "320003", "A": "x02220",
        "Am": "x02210", "Em": "022000", "Dm": "xx0231",
        "A7": "x02020", "B7": "x21202", "C7": "x32310", "D7": "xx0212", "E7": "020100", "G7": "320001",
        "Am7": "x02010", "Em7": "022030", "Dm7": "xx0211",
        "Asus2": "x02200", "Asus4": "x02230", "Dsus2": "xx0230", "Dsus4": "xx0233", "Esus4": "022200",
        "Cmaj7": "x32000", "Fmaj7": "xx3210", "Amaj7": "x02120", "Dmaj7": "xx0222", "Gmaj7": "320002",
        "Cadd9": "x32030", "A7sus4": "x02030", "E7sus4": "020200", "D6": "xx0202", "A6": "x02222", "Am6": "x02212", "Em6": "022020",
        "Bdim": "x2343x", "Edim": "0120xx",
    ]

    /// Kök 6. telde (E biçimi) ve 5. telde (A biçimi) barre kalıpları: kökten göreli perdeler (nil: çalınmaz).
    private static let eForm: [String: [Int?]] = [
        "": [0, 2, 2, 1, 0, 0], "m": [0, 2, 2, 0, 0, 0], "7": [0, 2, 0, 1, 0, 0], "m7": [0, 2, 0, 0, 0, 0],
        "sus4": [0, 2, 2, 2, 0, 0], "7sus4": [0, 2, 0, 2, 0, 0], "m6": [0, 2, 2, 0, 2, 0], "6": [0, 2, 2, 1, 2, 0],
    ]
    private static let aForm: [String: [Int?]] = [
        "": [nil, 0, 2, 2, 2, 0], "m": [nil, 0, 2, 2, 1, 0], "7": [nil, 0, 2, 0, 2, 0], "m7": [nil, 0, 2, 0, 1, 0],
        "maj7": [nil, 0, 2, 1, 2, 0], "sus2": [nil, 0, 2, 2, 0, 0], "sus4": [nil, 0, 2, 2, 3, 0], "7sus4": [nil, 0, 2, 0, 3, 0],
        "dim": [nil, 0, 1, 2, 1, nil], "m7b5": [nil, 0, 1, 0, 1, nil], "aug": [nil, 0, 3, 2, 2, nil],
        "6": [nil, 0, 2, 2, 2, 2], "m6": [nil, 0, 2, 2, 1, 2], "add9": [nil, 0, 2, 4, 0, 0], "9": [nil, 0, -1, 0, 0, 0],
    ]

    /// "Amin" → ("A", "m"), "CM7" → ("C", "maj7"), "D/F#" → ("D", ""). Desteklenmeyende nil.
    static func simplify(_ token: String) -> (root: String, quality: String)? {
        let chars = Array(token.trimmingCharacters(in: .whitespaces))
        guard let first = chars.first, ("A"..."G").contains(first) else { return nil }
        var root = String(first)
        var i = 1
        if i < chars.count, chars[i] == "#" || chars[i] == "b" { root.append(chars[i]); i += 1 }
        var quality = String(chars[i...])
        // Bas notasını at ("D/F#"), "6/9" sayısal eki değil
        if let slash = quality.firstIndex(of: "/"), quality != "6/9" {
            let after = quality[quality.index(after: slash)...]
            if let c = after.first, ("A"..."G").contains(c) { quality = String(quality[..<slash]) }
        }
        if let mapped = qualityMap[quality] { quality = mapped }
        guard qualities.contains(quality), pc[root] != nil else { return nil }
        return (root, quality)
    }

    private static func parseFrets(_ s: String) -> [Int] {
        s.map { $0 == "x" ? -1 : Int(String($0)) ?? 0 }
    }

    private static func barreShape(_ form: [Int?], fret: Int, name: String) -> Shape? {
        if form.contains(where: { if let x = $0 { return fret + x < 0 } else { return false } }) { return nil }
        let frets = form.map { $0 == nil ? -1 : fret + $0! }
        return Shape(frets: frets, barre: fret >= 1 ? fret : nil, name: name)
    }

    /// Akorun tutuşları: önce açık tutuş (varsa), sonra en alçak perdedeki barre.
    static func shapes(root: String, quality: String) -> [Shape] {
        guard let p = pc[root] else { return [] }
        var result: [Shape] = []
        for spelling in [sharps[p], flats[p]] {
            if let o = open[spelling + quality] {
                result.append(Shape(frets: parseFrets(o), barre: nil, name: "Açık tutuş"))
                break
            }
        }
        var barres: [Shape] = []
        let eFret = (p - 4 + 12) % 12 == 0 ? 12 : (p - 4 + 12) % 12
        let aFret = (p - 9 + 12) % 12 == 0 ? 12 : (p - 9 + 12) % 12
        if let f = eForm[quality], let s = barreShape(f, fret: eFret, name: "Barre, \(eFret). perde (kök 6. telde)") { barres.append(s) }
        if let f = aForm[quality], let s = barreShape(f, fret: aFret, name: "Barre, \(aFret). perde (kök 5. telde)") { barres.append(s) }
        return result + barres.sorted { ($0.barre ?? 0) < ($1.barre ?? 0) }
    }

    /// Akor adından tutuşlar (desteklenmiyorsa boş).
    static func shapes(for chordName: String) -> [Shape] {
        guard let c = simplify(chordName) else { return [] }
        return shapes(root: c.root, quality: c.quality)
    }
}
