import Foundation

// MARK: - CatalogSnapshot
//
// `shared/catalog/catalog.deflate` (uygulamaya gömülü seed) ve cihazdaki birleşik kopyanın JSON biçimi.
// Alanlar shared/src/types.ts ile birebir aynıdır; Firestore `songs/{id}` dokümanı da aynı alanları taşır.

nonisolated struct CatalogSnapshot: Codable {
    var seq: Int
    var count: Int
    var publishedAt: String
    var songs: [CatalogSongRecord]
}

nonisolated struct CatalogSongRecord: Codable, Identifiable, Hashable {
    /// Eski docId ile aynı (sayısal metin). Repertuarlardaki songIds bu değere bağlıdır.
    let id: String
    var artist: String
    var songName: String
    var originalKey: String
    var content: String
    var artistSlug: String
    var slug: String
    /// Tekil artan değişiklik sayacı; fark senkronu `seq > lastSeq` ile çalışır.
    var seq: Int
    var createdAt: String?
    var addedBy: String?
    /// Silinen şarkı farkı taşısın diye kayıt kalır, bu alan true olur.
    var deleted: Bool?

    var isDeleted: Bool { deleted == true }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: CatalogSongRecord, rhs: CatalogSongRecord) -> Bool { lhs.id == rhs.id && lhs.seq == rhs.seq }
}

extension CatalogSongRecord {
    private static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso = ISO8601DateFormatter()

    var createdDate: Date? {
        guard let createdAt else { return nil }
        return Self.isoWithFraction.date(from: createdAt) ?? Self.iso.date(from: createdAt)
    }

    /// Uygulamanın geri kalanının kullandığı modele dönüştürür (id → docId).
    func toLocalSong() -> LocalSong {
        LocalSong(
            docId: id,
            artist: artist,
            songName: songName,
            originalKey: originalKey,
            content: content,
            addedBy: addedBy,
            ownerId: nil,
            createdAt: createdDate,
            status: "approved"
        )
    }
}
