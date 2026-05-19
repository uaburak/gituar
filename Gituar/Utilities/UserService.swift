import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

class UserService: ObservableObject {
    static let shared = UserService()
    private let db = Firestore.firestore()
    
    @Published var currentUserProfile: UserProfile?
    
    private init() {}
    
    func isUsernameTaken(_ username: String) async throws -> Bool {
        let snapshot = try await db.collection("users")
            .whereField("username", isEqualTo: username.lowercased())
            .getDocuments()
        return !snapshot.isEmpty
    }
    
    func saveUserProfile(_ profile: UserProfile) async throws {
        try db.collection("users").document(profile.uid).setData(from: profile)
        DispatchQueue.main.async {
            self.currentUserProfile = profile
        }
    }
    
    func fetchUserProfile(uid: String) async throws -> UserProfile? {
        let doc = try await db.collection("users").document(uid).getDocument()
        let profile = try? doc.data(as: UserProfile.self)
        DispatchQueue.main.async {
            self.currentUserProfile = profile
        }
        return profile
    }
    
    // MARK: - Delete Account
    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else { return }
        let uid = user.uid
        
        // 1. Delete user document from Firestore
        try await db.collection("users").document(uid).delete()
        
        // 2. Delete the user authentication record
        try await user.delete()
        
        // 3. Clear local state
        DispatchQueue.main.async {
            self.currentUserProfile = nil
        }
    }
}
