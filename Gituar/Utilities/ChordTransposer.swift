import Foundation

// MARK: - ChordTransposer
//
// Akor satırı tespiti ve transpoze için saf fonksiyonlar — UI'dan bağımsız.

nonisolated enum ChordTransposer {

    /// Şarkı içeriğinin tek bir satırı; akor satırı olup olmadığı bir kez hesaplanır.
    struct SheetLine: Identifiable, Hashable, Sendable {
        let id: Int
        let text: String
        let isChordLine: Bool
    }

    /// Ton seçicide gösterilen notalar.
    static let selectableKeys = ["C", "C#", "Db", "D", "D#", "Eb", "E", "F", "F#", "Gb", "G", "G#", "Ab", "A", "A#", "Bb", "B"]

    private static let sharpScale = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private static let flatScale  = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
    private static let semitones: [String: Int] = [
        "C": 0, "B#": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "Fb": 4,
        "F": 5, "E#": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10,
        "B": 11, "Cb": 11
    ]
    private static let qualityKeywords: [[Character]] = ["maj", "min", "dim", "aug", "sus", "add"].map(Array.init)

    // MARK: - Public API

    static func parse(_ content: String) -> [SheetLine] {
        content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .enumerated()
            .map { SheetLine(id: $0.offset, text: $0.element, isChordLine: isChordLine($0.element)) }
    }

    /// "C#m" → "C#". Nota ile başlamıyorsa "C" döner.
    static func rootNote(of key: String) -> String {
        let chars = Array(key.trimmingCharacters(in: .whitespaces))
        var index = 0
        return readNote(chars, &index) ?? "C"
    }

    /// Orijinal tondan seçilen tona en kısa yarım ses farkı (−5…+6).
    static func semitoneOffset(from originalKey: String, to targetRoot: String) -> Int {
        guard let from = semitones[rootNote(of: originalKey)],
              let to = semitones[targetRoot] else { return 0 }
        let up = ((to - from) % 12 + 12) % 12
        return up > 6 ? up - 12 : up
    }

    /// Hedef ton bemollü yazılıyorsa (Bb, Eb… ya da F / Dm, Gm, Cm, Fm) akorlar da bemolle yazılır.
    static func prefersFlats(targetRoot: String, originalKey: String) -> Bool {
        if targetRoot.hasSuffix("b") { return true }
        if targetRoot.hasSuffix("#") { return false }
        let trimmedKey = originalKey.trimmingCharacters(in: .whitespaces)
        let quality = trimmedKey.dropFirst(rootNote(of: trimmedKey).count)
        let isMinor = quality.hasPrefix("m") && !quality.hasPrefix("maj")
        return isMinor ? ["D", "G", "C", "F"].contains(targetRoot) : targetRoot == "F"
    }

    static func isChordLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return false }
        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("x") || lowered.contains("intro") { return true }
        // Tab satırları (e|---0---|) akor satırı değildir
        if trimmed.contains("--") || trimmed.contains("|-") { return false }

        let tokens = trimmed.split(whereSeparator: isSeparator)
        guard !tokens.isEmpty else { return false }
        let chordCount = tokens.filter { parseChord($0) != nil }.count
        return Double(chordCount) / Double(tokens.count) >= 0.5
    }

    /// Satırdaki akorları `offset` yarım ses kaydırır. Akor olmayan kelimelere ("Nakarat:", "x2") dokunmaz;
    /// akor uzayıp kısaldığında aradaki boşlukları ayarlayarak sözlerle hizayı korur.
    static func transpose(_ line: String, by offset: Int, preferFlats: Bool = false) -> String {
        let shift = ((offset % 12) + 12) % 12
        guard shift != 0 else { return line }

        var result = ""
        var token = ""
        var spaceRun = 0
        var debt = 0 // > 0: akor uzadı, sonraki boşluklardan düş · < 0: kısaldı, boşluk ekle

        func flushToken() {
            guard !token.isEmpty else { return }
            if let chord = parseChord(Substring(token)) {
                let transposed = chord.transposed(by: shift, preferFlats: preferFlats)
                debt += transposed.count - token.count
                result += transposed
            } else {
                result += token
            }
            token = ""
        }

        func flushSpaces(atLineEnd: Bool = false) {
            guard spaceRun > 0 else { return }
            var count = spaceRun
            if debt > 0 {
                let cut = min(debt, count - 1)
                count -= cut
                debt -= cut
            } else if debt < 0, !atLineEnd {
                count -= debt
                debt = 0
            }
            result += String(repeating: " ", count: count)
            spaceRun = 0
        }

        for character in line {
            if character == " " {
                flushToken()
                spaceRun += 1
            } else if isSeparator(character) {
                flushToken()
                flushSpaces()
                result.append(character)
            } else {
                flushSpaces()
                token.append(character)
            }
        }
        flushToken()
        flushSpaces(atLineEnd: true)
        return result
    }

    // MARK: - Chord parsing

    private struct ParsedChord {
        let root: String
        let quality: String
        let bass: String?

        func transposed(by shift: Int, preferFlats: Bool) -> String {
            var result = ChordTransposer.transposeNote(root, by: shift, preferFlats: preferFlats) + quality
            if let bass {
                result += "/" + ChordTransposer.transposeNote(bass, by: shift, preferFlats: preferFlats)
            }
            return result
        }
    }

    private static func transposeNote(_ note: String, by shift: Int, preferFlats: Bool) -> String {
        guard let index = semitones[note] else { return note }
        return (preferFlats ? flatScale : sharpScale)[(index + shift) % 12]
    }

    /// Akorları birbirinden ayıran karakterler: "Am - Dm | G (x2)" gibi yazımlar için.
    private static func isSeparator(_ character: Character) -> Bool {
        character.isWhitespace || "-–—,|()[]".contains(character)
    }

    private static func isDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }

    /// `index` konumundan bir nota (A–G + isteğe bağlı #/b) okur ve `index`'i ilerletir.
    private static func readNote(_ chars: [Character], _ index: inout Int) -> String? {
        guard index < chars.count, ("A"..."G").contains(chars[index]) else { return nil }
        var note = String(chars[index])
        index += 1
        if index < chars.count, chars[index] == "#" || chars[index] == "b" {
            note.append(chars[index])
            index += 1
        }
        return note
    }

    /// "C#m7", "Dsus4", "G7b9", "D/F#" gibi bir akoru parçalarına ayırır; akor değilse nil.
    private static func parseChord(_ token: Substring) -> ParsedChord? {
        let chars = Array(token)
        var index = 0
        guard let root = readNote(chars, &index) else { return nil }
        let qualityStart = index

        while index < chars.count {
            let character = chars[index]
            if character == "/" {
                let next = index + 1
                // "C6/9" gibi sayısal ek
                if next < chars.count, isDigit(chars[next]) {
                    index = next
                    continue
                }
                // "D/F#" gibi bas notası — akorun sonunda olmalı
                var bassEnd = next
                guard let bass = readNote(chars, &bassEnd), bassEnd == chars.count else { return nil }
                return ParsedChord(root: root, quality: String(chars[qualityStart..<index]), bass: bass)
            }
            if let keyword = qualityKeywords.first(where: { chars[index...].starts(with: $0) }) {
                index += keyword.count
            } else if "mM+°ø".contains(character) || isDigit(character) {
                index += 1
            } else if character == "#" || character == "b", index + 1 < chars.count, isDigit(chars[index + 1]) {
                index += 1 // b5, #9 gibi alterasyonlar
            } else {
                return nil
            }
        }
        return ParsedChord(root: root, quality: String(chars[qualityStart...]), bass: nil)
    }
}
