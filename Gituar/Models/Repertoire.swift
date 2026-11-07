import Foundation
import FirebaseFirestore

struct Repertoire: Identifiable, Codable {
    @DocumentID var id: String?
    var name: String
    var songIds: [String]
    var ownerId: String // For future login
    var createdAt: Date
    var isPublic: Bool?
    var sourceId: String? // Orijinal repertuarın ID'si
    /// Herkese açık repertuarın web adresi: gituar.com/repertuar/{ownerUsername}/{slug}/
    /// Kullanıcı adı tekildir, slug da sahibin herkese açık repertuarları arasında tekil tutulur ("sahne", "sahne-2").
    var ownerUsername: String?
    var slug: String?
}
