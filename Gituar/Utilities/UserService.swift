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
        // merge: döküman zaten varsa isAdmin / blockedUsers gibi alanlar silinmesin
        try db.collection("users").document(profile.uid).setData(from: profile, merge: true)
        DispatchQueue.main.async {
            self.currentUserProfile = profile
        }
    }
    
    /// - Returns: Profil dökümanı yoksa nil. Ağ/yetki hatasında throw eder — "profil yok" ile karıştırılmamalı.
    func fetchUserProfile(uid: String) async throws -> UserProfile? {
        let doc = try await db.collection("users").document(uid).getDocument()
        let profile = try? doc.data(as: UserProfile.self)
        DispatchQueue.main.async {
            self.currentUserProfile = profile
        }
        return profile
    }
    
    func getPublicUserProfile(uid: String) async throws -> UserProfile? {
        let doc = try await db.collection("users").document(uid).getDocument()
        return try? doc.data(as: UserProfile.self)
    }
    
    // MARK: - Delete Account

    enum AccountDeletionError: LocalizedError {
        /// Firebase hesap silme için yakın zamanda giriş yapılmış olmasını ister.
        case requiresRecentLogin

        var errorDescription: String? {
            "Güvenlik nedeniyle hesabınızı silmeden önce yeniden giriş yapmanız gerekiyor."
        }
    }

    /// Firebase'in "yakın zamanda giriş" penceresi ~5 dk; güvenli tarafta kalmak için biraz altı.
    private let recentLoginWindow: TimeInterval = 4.5 * 60

    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else { return }
        let uid = user.uid
        let userRef = db.collection("users").document(uid)

        // Oturum eskiyse Auth silme işlemi reddedilir. Bunu veriler silinmeden ÖNCE kontrol et —
        // aksi halde profil silinip hesap yerinde kalıyor.
        if let lastSignIn = user.metadata.lastSignInDate,
           Date().timeIntervalSince(lastSignIn) > recentLoginWindow {
            throw AccountDeletionError.requiresRecentLogin
        }

        // 1. Delete the user's private subcollections (best-effort)
        for subcollection in ["repertoires", "preferences"] {
            guard let snapshot = try? await userRef.collection(subcollection).getDocuments() else { continue }
            var documents = snapshot.documents[...]
            while !documents.isEmpty {
                let batch = db.batch()
                documents.prefix(400).forEach { batch.deleteDocument($0.reference) }
                documents = documents.dropFirst(400)
                try? await batch.commit()
            }
        }

        // 2. Delete user document from Firestore
        try await userRef.delete()

        // 3. Delete the user authentication record
        do {
            try await user.delete()
        } catch let error as NSError where error.code == AuthErrorCode.requiresRecentLogin.rawValue {
            throw AccountDeletionError.requiresRecentLogin
        }

        // 4. Clear local state
        DispatchQueue.main.async {
            self.currentUserProfile = nil
        }
    }
}
