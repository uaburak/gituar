import Foundation
import FirebaseFirestore

struct Song: Identifiable, Codable, Hashable, Sendable {
    @DocumentID var id: String?
    var docId: String
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
        status: String? = nil
    ) {
        _id          = DocumentID(wrappedValue: id)
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
        self.status       = status
    }

    // MARK: - Custom Codable (fixes @DocumentID with JSONEncoder)
    // @DocumentID uses a non-standard internal key; we map it to plain "id" for local JSON cache.
    enum CodingKeys: String, CodingKey {
        case id, docId, artist, songName, originalKey, content, createdAt
        case totalViews, recentViews, repertoireAdds
        case ownerId, status
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Decode docId first so we can use it as fallback for id.
        // @DocumentID is only populated by Firestore; JSON cache stores it as plain String?.
        // When id is nil (cache load), SwiftUI Identifiable breaks — every row shows the same item.
        docId      = try c.decode(String.self,  forKey: .docId)
        let rawId  = try c.decodeIfPresent(String.self, forKey: .id)
        _id        = DocumentID(wrappedValue: rawId ?? docId)   // ← fallback keeps id unique
        artist     = try c.decode(String.self,  forKey: .artist)
        songName   = try c.decode(String.self,  forKey: .songName)
        originalKey = try c.decode(String.self, forKey: .originalKey)
        content    = try c.decode(String.self,  forKey: .content)
        createdAt  = try c.decodeIfPresent(Date.self,   forKey: .createdAt)
        totalViews    = try c.decodeIfPresent(Int.self,    forKey: .totalViews)
        recentViews   = try c.decodeIfPresent(Int.self,    forKey: .recentViews)
        repertoireAdds = try c.decodeIfPresent(Int.self,   forKey: .repertoireAdds)
        ownerId    = try c.decodeIfPresent(String.self, forKey: .ownerId)
        status     = try c.decodeIfPresent(String.self, forKey: .status)
    }


    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id,          forKey: .id)
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
        try c.encodeIfPresent(status,     forKey: .status)
    }

    
    // Popülerlik Puanı Algoritması
    // Formula: (TotalViews * 0.1) + (RecentViews * 0.6) + (RepertoireAdds * 0.3)
    var popularityScore: Double {
        let wTotal = 0.1
        let wRecent = 0.6
        let wAdds = 0.3
        
        let total = Double(totalViews ?? 0)
        let recent = Double(recentViews ?? 0)
        let adds = Double(repertoireAdds ?? 0)
        
        return (total * wTotal) + (recent * wRecent) + (adds * wAdds)
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(docId)
    }
    
    static func == (lhs: Song, rhs: Song) -> Bool {
        return lhs.docId == rhs.docId
    }
}


