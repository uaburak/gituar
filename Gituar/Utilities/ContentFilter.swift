import Foundation

/// Kullanıcı içeriği için basit uygunsuz ifade filtresi (App Store Guideline 1.2: "a method for filtering
/// objectionable material"). Gönderilen şarkı yine editör onayından geçer; bu filtre bariz küfür ve hakareti
/// yayına gönderilmeden yakalar. Liste kelime başına eşleşir, Türkçe karakterler sadeleştirilerek karşılaştırılır.
enum ContentFilter {
    private static let blocked: [String] = [
        "amk", "aq", "amina", "aminakoyim", "amcik", "orospu", "orospucocugu", "pic", "pezevenk", "yarrak", "yarak",
        "siktir", "sikerim", "sikeyim", "sikik", "gavat", "kahpe", "ibne", "gotveren", "kaltak", "surtuk",
        "fuck", "fucking", "motherfucker", "shit", "bitch", "cunt", "pussy", "nigger", "faggot", "whore",
    ]

    private static func normalize(_ text: String) -> String {
        text.lowercased(with: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "ğ", with: "g")
            .replacingOccurrences(of: "ü", with: "u")
            .replacingOccurrences(of: "ş", with: "s")
            .replacingOccurrences(of: "ö", with: "o")
            .replacingOccurrences(of: "ç", with: "c")
    }

    /// Metinde engelli bir kelime varsa ilkini döndürür.
    static func firstObjectionableWord(in texts: String...) -> String? {
        let set = Set(blocked)
        for text in texts {
            let words = normalize(text).components(separatedBy: CharacterSet.letters.inverted)
            if let hit = words.first(where: { set.contains($0) }) { return hit }
        }
        return nil
    }
}
