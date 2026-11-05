import Foundation

// MARK: - Slug üretimi
//
// shared/src/turkish.ts içindeki `slugify` ile birebir aynı kurallar: Türkçe karakterler ASCII'ye,
// noktalama boşluğa, [a-z0-9 -] dışı silinir, boşluklar "-" olur, ardışık tireler tek tire.
// Web URL'leri (/akor/{artistSlug}/{slug}/) bu değerlerden üretildiği için kural değişmemelidir.

extension String {
    nonisolated var slugified: String {
        let punctuation: Set<Character> = ["'", "’", "\"", "?", "!", ",", ";", ".", ":", "_", "+", "(", ")", "[", "]", "&", "/", "\\"]
        var cleaned = ""
        for ch in turkeyNormalized {
            if punctuation.contains(ch) {
                cleaned.append(" ")
            } else if ch.isASCII && (ch.isLetter || ch.isNumber || ch == " " || ch == "-") {
                cleaned.append(ch)
            }
            // diğer karakterler atılır
        }
        let words = cleaned.split(whereSeparator: { $0 == " " }).map(String.init)
        var slug = words.joined(separator: "-")
        while slug.contains("--") { slug = slug.replacingOccurrences(of: "--", with: "-") }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "x" : slug
    }
}

/// Aynı sanatçıda aynı slug tekrar ederse -2, -3 ekler. Katalogda zaten var olan şarkıların slug'ı korunur.
nonisolated struct SlugAllocator {
    private var used: Set<String> = []
    private var existingById: [String: (artistSlug: String, slug: String)] = [:]

    init(existing: [String: (artistSlug: String, slug: String)]) {
        existingById = existing
        for (_, pair) in existing where !pair.artistSlug.isEmpty && !pair.slug.isEmpty {
            used.insert(pair.artistSlug + "/" + pair.slug)
        }
    }

    mutating func allocate(id: String, artist: String, songName: String) -> (artistSlug: String, slug: String) {
        if let pair = existingById[id], !pair.artistSlug.isEmpty, !pair.slug.isEmpty {
            return pair
        }
        let artistSlug = artist.slugified
        let base = songName.slugified
        var slug = base
        var n = 2
        while used.contains(artistSlug + "/" + slug) {
            slug = "\(base)-\(n)"
            n += 1
        }
        used.insert(artistSlug + "/" + slug)
        existingById[id] = (artistSlug, slug)
        return (artistSlug, slug)
    }
}
