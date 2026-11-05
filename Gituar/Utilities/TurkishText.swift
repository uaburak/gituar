import Foundation

// MARK: - Türkçe metin yardımcıları

nonisolated enum TurkishText {
    static let locale = Locale(identifier: "tr-TR")
}

extension String {
    /// Arama için normalize eder: küçük harfe çevirir ve Türkçe karakterleri ASCII karşılığına indirger
    /// (ç→c, ğ→g, ı/I/İ→i, ö→o, ş→s, ü→u). Diğer aksanlı harfler de (â, é…) sadeleştirilir.
    nonisolated var turkeyNormalized: String {
        var scalars = String.UnicodeScalarView()
        var needsFolding = false
        for scalar in unicodeScalars {
            switch scalar {
            case "A"..."Z": scalars.append(Unicode.Scalar(UInt8(scalar.value) + 32))
            case "ç", "Ç": scalars.append("c")
            case "ğ", "Ğ": scalars.append("g")
            case "ı", "İ": scalars.append("i")
            case "ö", "Ö": scalars.append("o")
            case "ş", "Ş": scalars.append("s")
            case "ü", "Ü": scalars.append("u")
            default:
                if !scalar.isASCII { needsFolding = true }
                scalars.append(scalar)
            }
        }
        let result = String(scalars)
        // Yukarıdaki tablo dışında kalan aksanlı harfler için (nadir) Foundation'a düş
        guard needsFolding else { return result }
        return result
            .lowercased(with: TurkishText.locale)
            .folding(options: .diacriticInsensitive, locale: TurkishText.locale)
    }

    /// Türkçe alfabe sırasına göre (ç, ğ, ı, ö, ş, ü doğru yerde) `other`'dan önce mi gelir?
    nonisolated func isOrderedBeforeInTurkish(_ other: String) -> Bool {
        compare(other, options: .caseInsensitive, range: nil, locale: TurkishText.locale) == .orderedAscending
    }
}

// MARK: - Şarkı arama

nonisolated enum SongSearch {
    /// Şarkı adı ve sanatçı üzerinde çok kelimeli arama yapar ("sezen gülümse" gibi).
    /// - Parameter ranked: true ise sorguyla başlayan sonuçlar öne alınır ve kalanlar ada göre sıralanır;
    ///   false ise listenin mevcut sırası korunur (repertuar sırası gibi).
    static func filter(_ songs: [Song], query: String, ranked: Bool = false) -> [Song] {
        let words = query.turkeyNormalized.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return songs }
        let fullQuery = words.joined(separator: " ")

        var matches: [(song: Song, name: String, rank: Int)] = []
        for song in songs {
            let name = song.songName.turkeyNormalized
            let artist = song.artist.turkeyNormalized
            guard words.allSatisfy({ name.contains($0) || artist.contains($0) }) else { continue }
            let rank = name.hasPrefix(fullQuery) ? 0 : (artist.hasPrefix(fullQuery) ? 1 : 2)
            matches.append((song, name, rank))
        }

        guard ranked else { return matches.map(\.song) }
        return matches
            .sorted { $0.rank != $1.rank ? $0.rank < $1.rank : $0.name < $1.name }
            .map(\.song)
    }
}
