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
    @Published var isInitialCheckDone: Bool = false
    @Published var userProfile: UserProfile? = nil
    /// Profil bağlantı hatası yüzünden okunamadı ve daha önce tamamlandığı da bilinmiyor.
    @Published var profileCheckFailed: Bool = false

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
                    // Çıkış yapan kullanıcının profili (ve admin yetkisi) misafir modunda kalmasın
                    self?.userProfile = nil
                    self?.isProfileComplete = false
                    self?.profileCheckFailed = false
                    self?.isInitialCheckDone = true // Oturum yoksa kontrol bitti
                }
            }
        }
    }

    private func profileCompleteKey(_ uid: String) -> String { "profileComplete_\(uid)" }

    func checkUserProfile(uid: String) {
        isCheckingProfile = true
        profileCheckFailed = false
        if userProfile?.uid != uid { userProfile = nil }

        Task { @MainActor [weak self] in
            do {
                let profile = try await UserService.shared.fetchUserProfile(uid: uid)
                guard let self, self.currentUser?.uid == uid else { return }
                self.userProfile = profile
                self.isProfileComplete = (profile != nil)
                UserDefaults.standard.set(profile != nil, forKey: self.profileCompleteKey(uid))
            } catch {
                guard let self, self.currentUser?.uid == uid else { return }
                // Bağlantı hatası "profil yok" demek değildir. Profilin daha önce tamamlandığını
                // biliyorsak devam et; bilmiyorsak profil formunu açmak yerine tekrar denemeyi öner
                // (form mevcut profilin üzerine yazabilirdi).
                if UserDefaults.standard.bool(forKey: self.profileCompleteKey(uid)) {
                    self.isProfileComplete = true
                } else {
                    self.profileCheckFailed = true
                }
                print("⚠️ checkUserProfile: \(error.localizedDescription)")
            }
            self?.isCheckingProfile = false
            self?.isInitialCheckDone = true // Profil kontrolü bitti, artık her şey hazır
        }
    }

    /// Profil bağlantı hatası yüzünden okunamadıysa (ör. açılışta internet yoktu) yeniden dener.
    func refreshProfileIfNeeded() {
        guard let uid = currentUser?.uid, !isCheckingProfile else { return }
        guard profileCheckFailed || (isProfileComplete && userProfile == nil) else { return }
        checkUserProfile(uid: uid)
    }

    /// CompleteProfileView profili kaydettikten sonra çağırır.
    func profileDidComplete(_ profile: UserProfile) {
        userProfile = profile
        isProfileComplete = true
        profileCheckFailed = false
        UserDefaults.standard.set(true, forKey: profileCompleteKey(profile.uid))
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
        // Profildeki ad her zaman dolu; Apple ile girişte Auth displayName çoğu zaman boş gelir
        if let profile = userProfile {
            let fullName = "\(profile.firstName) \(profile.lastName)".trimmingCharacters(in: .whitespaces)
            if !fullName.isEmpty { return fullName }
        }
        if let name = currentUser?.displayName, !name.isEmpty { return name }
        return currentUser?.email?.components(separatedBy: "@").first ?? "Kullanıcı"
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
                errorMessage = "Apple ile giriş şu anda kullanılamıyor.\nCihazında Apple hesabına giriş yaptığından emin ol ve tekrar dene."
            } else {
                errorMessage = friendlyError(error)
            }
        }
    }

    // MARK: - E-posta ve şifre (web ile aynı)

    func signInWithEmail(_ email: String, password: String) {
        runEmailAuth { try await Auth.auth().signIn(withEmail: email, password: password) }
    }

    func signUpWithEmail(_ email: String, password: String) {
        runEmailAuth { try await Auth.auth().createUser(withEmail: email, password: password) }
    }

    /// Şifre sıfırlama bağlantısı gönderir.
    func sendPasswordReset(_ email: String) {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            errorMessage = "Şifre sıfırlama için önce e-posta adresini yaz."
            return
        }
        Task { @MainActor in
            isLoading = true
            defer { isLoading = false }
            do {
                try await Auth.auth().sendPasswordReset(withEmail: trimmed)
                errorMessage = "Şifre sıfırlama bağlantısı \(trimmed) adresine gönderildi."
            } catch {
                errorMessage = friendlyError(error)
            }
        }
    }

    private func runEmailAuth(_ op: @escaping () async throws -> AuthDataResult) {
        errorMessage = nil
        Task { @MainActor in
            isLoading = true
            defer { isLoading = false }
            do {
                _ = try await op()
            } catch {
                errorMessage = (error as NSError).code == AuthErrorCode.invalidCredential.rawValue
                    ? "E-posta ya da şifre hatalı." : friendlyError(error)
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
        case AuthErrorCode.networkError.rawValue: return "İnternet bağlantısı yok. Bağlantını kontrol et."
        case AuthErrorCode.userDisabled.rawValue: return "Bu hesap devre dışı bırakılmış."
        case AuthErrorCode.invalidCredential.rawValue: return "Kimlik doğrulanamadı. Lütfen tekrar dene."
        case AuthErrorCode.userNotFound.rawValue: return "Bu e-posta ile kayıtlı hesap bulunamadı."
        case AuthErrorCode.wrongPassword.rawValue: return "Şifre hatalı."
        case AuthErrorCode.invalidEmail.rawValue: return "E-posta adresi geçersiz."
        case AuthErrorCode.emailAlreadyInUse.rawValue: return "Bu e-posta zaten kayıtlı. Giriş yapmayı dene."
        case AuthErrorCode.weakPassword.rawValue: return "Şifre en az 6 karakter olmalı."
        case AuthErrorCode.operationNotAllowed.rawValue: return "Bu giriş yöntemi henüz açık değil."
        case AuthErrorCode.accountExistsWithDifferentCredential.rawValue: return "Bu e-posta başka bir giriş yöntemiyle kayıtlı; o yöntemle giriş yap."
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
