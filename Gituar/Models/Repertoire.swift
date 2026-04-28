import Foundation
import FirebaseFirestore

struct Repertoire: Identifiable, Codable {
    @DocumentID var id: String?
    var name: String
    var songIds: [String]
    var ownerId: String // For future login
    var createdAt: Date
}
