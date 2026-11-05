import Foundation
import FirebaseFirestore

struct Song: Identifiable, Codable, Hashable, Sendable {
    /// Firestore document ID — set automatically by Firestore when reading from DB.
    /// When decoded from local JSON (bundle / cache), this is nil (to avoid [I-FST000002] warnings).
    @DocumentID var firestoreId: String?
    /// Stable local identity used for Identifiable, caching, and all in-memory operations.
    var docId: String
    /// Identifiable conformance — always uses docId so SwiftUI never sees nil.
    var id: String { docId }

    var artist: String
    var songName: String
    var originalKey: String
    var content: String
    var createdAt: Date?
    
    // Metrikler
    var totalViews: Int?
    var recentViews: Int?
    var repertoireAdds: Int?
    
    // Sahiplik
    var ownerId: String?
    var addedBy: String?
    
    // Yayınlama Durumu
    var status: String? // "draft", "pending", "approved", "rejected"
    
    // MARK: - Memberwise init (preserved after adding custom Codable)
    init(
        id: String? = nil,
        docId: String,
        artist: String,
        songName: String,
        originalKey: String,
        content: String,
        createdAt: Date? = nil,
        totalViews: Int? = nil,
        recentViews: Int? = nil,
        repertoireAdds: Int? = nil,
        ownerId: String? = nil,
        addedBy: String? = nil,
        status: String? = nil
    ) {
        _firestoreId = DocumentID(wrappedValue: id)
        self.docId        = docId
        self.artist       = artist
        self.songName     = songName
        self.originalKey  = originalKey
        self.content      = content
        self.createdAt    = createdAt
        self.totalViews   = totalViews
        self.recentViews  = recentViews
        self.repertoireAdds = repertoireAdds
        self.ownerId      = ownerId
        self.addedBy      = addedBy
        self.status       = status
    }

    // MARK: - Custom Codable (fixes @DocumentID with JSONEncoder)
    // @DocumentID uses a non-standard internal key; we map it to plain "id" for local JSON cache.
    enum CodingKeys: String, CodingKey {
        case id, docId, artist, songName, originalKey, content, createdAt
        case totalViews, recentViews, repertoireAdds
        case ownerId, addedBy, status
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        docId      = try c.decode(String.self,  forKey: .docId)
        artist     = try c.decode(String.self,  forKey: .artist)
        songName   = try c.decode(String.self,  forKey: .songName)
        originalKey = try c.decode(String.self, forKey: .originalKey)
        content    = try c.decode(String.self,  forKey: .content)
        // createdAt normalde Firestore Timestamp'tir. Eski sürümlerin düzenleme akışı bazı dökümanlara
        // sayı (referans tarihinden itibaren saniye) olarak yazdı; bu yüzden tüm şarkı decode
        // edilemiyordu — iki biçimi de kabul et.
        if let date = try? c.decodeIfPresent(Date.self, forKey: .createdAt) {
            createdAt = date
        } else if let seconds = try? c.decodeIfPresent(Double.self, forKey: .createdAt) {
            createdAt = Date(timeIntervalSinceReferenceDate: seconds)
        } else {
            createdAt = nil
        }
        totalViews    = try c.decodeIfPresent(Int.self,    forKey: .totalViews)
        recentViews   = try c.decodeIfPresent(Int.self,    forKey: .recentViews)
        repertoireAdds = try c.decodeIfPresent(Int.self,   forKey: .repertoireAdds)
        ownerId    = try c.decodeIfPresent(String.self, forKey: .ownerId)
        addedBy    = try c.decodeIfPresent(String.self, forKey: .addedBy)
        status     = try c.decodeIfPresent(String.self, forKey: .status)
        // @DocumentID is ONLY set by Firestore when reading from the database.
        // When decoding from local JSON (cache or bundle), we always leave id = nil.
        // Identity is handled exclusively via docId — this eliminates the Firestore warning
        // "[I-FST000002] Attempting to initialize or set a @DocumentID property with a non-nil value".
        _firestoreId = DocumentID(wrappedValue: nil)
    }



    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(firestoreId, forKey: .id)
        try c.encode(docId,               forKey: .docId)
        try c.encode(artist,              forKey: .artist)
        try c.encode(songName,            forKey: .songName)
        try c.encode(originalKey,         forKey: .originalKey)
        try c.encode(content,             forKey: .content)
        try c.encodeIfPresent(createdAt,  forKey: .createdAt)
        try c.encodeIfPresent(totalViews,    forKey: .totalViews)
        try c.encodeIfPresent(recentViews,   forKey: .recentViews)
        try c.encodeIfPresent(repertoireAdds, forKey: .repertoireAdds)
        try c.encodeIfPresent(ownerId,    forKey: .ownerId)
        try c.encodeIfPresent(addedBy,    forKey: .addedBy)
        try c.encodeIfPresent(status,     forKey: .status)
    }

    
    func hash(into hasher: inout Hasher) {
        hasher.combine(docId)
    }
    
    static func == (lhs: Song, rhs: Song) -> Bool {
        return lhs.docId == rhs.docId
    }

    /// `==` yalnızca docId'ye bakar; bu ise iki kaydın aynı şarkı içeriğini taşıyıp taşımadığını söyler.
    func hasSameContent(as other: Song) -> Bool {
        ownerId == other.ownerId &&
        songName == other.songName &&
        artist == other.artist &&
        originalKey == other.originalKey &&
        content == other.content
    }
}
