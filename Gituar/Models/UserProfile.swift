import Foundation
import FirebaseFirestore

struct UserProfile: Identifiable, Codable {
    @DocumentID var id: String?
    var uid: String
    var firstName: String
    var lastName: String
    var username: String
    var email: String?
    var photoUrl: String?
    var createdAt: Date?
}
