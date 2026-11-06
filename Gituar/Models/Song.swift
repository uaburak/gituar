import Foundation

/// Uygulamanın tek şarkı modeli. Tüm şarkılar Gituar API'sinden (Cloudflare D1) gelir.
///
/// Liste uçları (`/v1/songs`, `/v1/search`, `/v1/artists/{slug}`, `/v1/songs/batch`) içeriği taşımaz:
/// bu durumda `content` boştur ve `hasContent == false` olur. Şarkı açılınca `/v1/songs/{id}` ile tamamlanır.
nonisolated struct Song: Identifiable, Hashable, Sendable {
    /// API kimliği (ör. "bk016"). Repertuar, tercih ve "son çalınanlar" kayıtları bu değere bağlıdır.
    var docId: String
    /// Identifiable — her zaman docId.
    var id: String { docId }

    var artist: String
    var songName: String
    var originalKey: String
    var content: String
    var createdAt: Date?
    var updatedAt: Date?

    var artistSlug: String?
    var slug: String?
    /// Popülerlik puanı (liste sıralaması için; yalnızca bilgi amaçlı).
    var score: Double?

    // Sahiplik (yalnızca tam kayıtta gelir)
    var ownerId: String?
    var addedBy: String?

    /// "draft", "pending", "approved", "rejected"
    var status: String?

    /// Tam kayıt mı (söz/akor içeriği yüklendi mi)?
    var hasContent: Bool

    init(
        docId: String,
        artist: String,
        songName: String,
        originalKey: String,
        content: String = "",
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        artistSlug: String? = nil,
        slug: String? = nil,
        score: Double? = nil,
        ownerId: String? = nil,
        addedBy: String? = nil,
        status: String? = nil,
        hasContent: Bool = true
    ) {
        self.docId = docId
        self.artist = artist
        self.songName = songName
        self.originalKey = originalKey
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.artistSlug = artistSlug
        self.slug = slug
        self.score = score
        self.ownerId = ownerId
        self.addedBy = addedBy
        self.status = status
        self.hasContent = hasContent
    }

    /// Sanatçı sayfası için slug — API her zaman verir; yoksa addan üretilir.
    var resolvedArtistSlug: String {
        if let artistSlug, !artistSlug.isEmpty { return artistSlug }
        return artist.slugified
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(docId)
    }

    static func == (lhs: Song, rhs: Song) -> Bool {
        lhs.docId == rhs.docId
    }

    /// Liste kaydının üzerine tam kaydı (içerik, sahip) bindirir; elde olan alanları korur.
    func merged(with full: Song) -> Song {
        var result = full
        if result.artistSlug == nil { result.artistSlug = artistSlug }
        if result.slug == nil { result.slug = slug }
        if result.score == nil { result.score = score }
        return result
    }
}
