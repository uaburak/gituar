import Foundation
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import AuthenticationServices
import CryptoKit
import Combine

class AuthViewModel: ObservableObject {
    @Published var currentUser: FirebaseAuth.User? = nil
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var isGuestMode: Bool = false
    @Published var isProfileComplete: Bool = false
    @Published var isCheckingProfile: Bool = false
    @Published var userProfile: UserProfile? = nil

    var isAdmin: Bool {
        userProfile?.isAdmin ?? false
    }

    private var currentNonce: String?
    private var authStateHandle: AuthStateDidChangeListenerHandle?

    init() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.currentUser = user
                if let user = user {
                    self?.isGuestMode = false
                    self?.checkUserProfile(uid: user.uid)
                } else {
                    self?.isProfileComplete = false
                }
            }
        }
    }

    func checkUserProfile(uid: String) {
        isCheckingProfile = true
        Task { [weak self] in
            let profile = try? await UserService.shared.fetchUserProfile(uid: uid)
            DispatchQueue.main.async {
                self?.userProfile = profile
                self?.isProfileComplete = (profile != nil)
                self?.isCheckingProfile = false
            }
        }
    }

    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    // MARK: - Computed Properties

    var isSignedIn: Bool {
        currentUser != nil || isGuestMode
    }

    var displayName: String {
        if isGuestMode { return "Misafir" }
        return currentUser?.displayName
            ?? currentUser?.email?.components(separatedBy: "@").first
            ?? "Kullanıcı"
    }

    var userEmail: String {
        currentUser?.email ?? (isGuestMode ? "Misafir Kullanıcı" : "")
    }

    var userInitials: String {
        if isGuestMode { return "M" }
        let name = displayName
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    var isRealUser: Bool {
        currentUser != nil && !isGuestMode
    }

    // MARK: - Google Sign In

    func signInWithGoogle() {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            errorMessage = "Firebase yapılandırması bulunamadı."
            return
        }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            errorMessage = "Pencere bulunamadı."
            return
        }

        isLoading = true
        errorMessage = nil

        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.isLoading = false
                    // Kullanıcı iptal ettiyse sessizce geç
                    let nsError = error as NSError
                    if nsError.code == GIDSignInError.canceled.rawValue { return }
                    self?.errorMessage = self?.friendlyError(error)
                    return
                }

                guard let user = result?.user,
                      let idToken = user.idToken?.tokenString else {
                    self?.isLoading = false
                    self?.errorMessage = "Google kimlik bilgileri alınamadı."
                    return
                }

                let credential = GoogleAuthProvider.credential(
                    withIDToken: idToken,
                    accessToken: user.accessToken.tokenString
                )

                Auth.auth().signIn(with: credential) { _, error in
                    DispatchQueue.main.async {
                        self?.isLoading = false
                        if let error = error {
                            self?.errorMessage = self?.friendlyError(error)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Apple Sign In

    func prepareAppleSignIn() -> String {
        let nonce = randomNonceString()
        currentNonce = nonce
        return sha256(nonce)
    }

    func handleAppleSignIn(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let nonce = currentNonce,
                  let appleIDToken = appleIDCredential.identityToken,
                  let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                errorMessage = "Apple ile giriş bilgileri alınamadı. Lütfen tekrar deneyin."
                return
            }

            let credential = OAuthProvider.appleCredential(
                withIDToken: idTokenString,
                rawNonce: nonce,
                fullName: appleIDCredential.fullName
            )

            isLoading = true
            errorMessage = nil
            Auth.auth().signIn(with: credential) { [weak self] _, error in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    if let error = error {
                        self?.errorMessage = self?.friendlyError(error)
                    }
                }
            }

        case .failure(let error):
            let nsError = error as NSError
            if nsError.domain == ASAuthorizationError.errorDomain,
               nsError.code == ASAuthorizationError.canceled.rawValue { return }
            if nsError.domain == "com.apple.AuthenticationServices.AuthorizationError",
               nsError.code == 1000 {
                errorMessage = "Apple ile giriş şu anda kullanılamıyor.\nXcode'da 'Sign In with Apple' capability'sini ekle ve Firebase Console'da Apple provider'ını etkinleştir."
            } else {
                errorMessage = friendlyError(error)
            }
        }
    }

    // MARK: - Misafir Modu

    func continueAsGuest() {
        isGuestMode = true
        errorMessage = nil
    }

    // MARK: - Sign Out

    func signOut() {
        isGuestMode = false
        GIDSignIn.sharedInstance.signOut()
        do {
            try Auth.auth().signOut()
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    // MARK: - Helpers

    private func friendlyError(_ error: Error) -> String {
        let nsError = error as NSError
        switch nsError.code {
        case 17020: return "İnternet bağlantısı yok. Bağlantını kontrol et."
        case 17004: return "Bu hesap devre dışı bırakılmış."
        case 17011: return "Bu e-posta ile kayıtlı hesap bulunamadı."
        default: return error.localizedDescription
        }
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess { fatalError("SecRandomCopyBytes failed: \(errorCode)") }
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}
