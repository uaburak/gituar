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
