import SwiftUI
import AuthenticationServices

/// Giriş: üstte logo, ortada e-posta ve şifre, altında yan yana Apple ve Google, en altta misafir.
struct AuthView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focused: Field?
    @State private var apple = AppleSignInCoordinator()
    private enum Field { case email, password }

    private var trimmed: String { email.trimmingCharacters(in: .whitespaces) }
    private var canSubmit: Bool { trimmed.contains("@") && trimmed.contains(".") && password.count >= 6 }

    var body: some View {
        NavigationStack {
            ZStack {
                // Sade, tek renk zemin
                Color(.systemBackground)
                    .ignoresSafeArea()
                    .onTapGesture { focused = nil }

                ScrollView {
                    VStack(spacing: 0) {
                        // Marka
                        VStack(spacing: 12) {
                            Image("Logo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 76, height: 76)
                                .shadow(color: .black.opacity(0.15), radius: 16, y: 8)
                            Text("Gituar")
                                .font(.system(size: 34, weight: .bold))
                            Text(isSignUp ? "Ücretsiz hesap oluştur" : "Hesabına giriş yap")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                                .contentTransition(.opacity)
                        }
                        .padding(.top, 72)
                        .padding(.bottom, 48)

                        // E-posta ve şifre
                        VStack(spacing: 12) {
                            Picker("", selection: $isSignUp.animation(.snappy)) {
                                Text("Giriş Yap").tag(false)
                                Text("Hesap Oluştur").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .controlSize(.large)
                            .padding(.bottom, 4)
                            .onChange(of: isSignUp) { _, _ in authViewModel.errorMessage = nil }

                            field {
                                TextField("E-posta", text: $email)
                                    .textContentType(.emailAddress)
                                    .keyboardType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .submitLabel(.next)
                                    .focused($focused, equals: .email)
                                    .onSubmit { focused = .password }
                            }
                            field {
                                SecureField(isSignUp ? "Şifre (en az 6 karakter)" : "Şifre", text: $password)
                                    .textContentType(isSignUp ? .newPassword : .password)
                                    .submitLabel(.go)
                                    .focused($focused, equals: .password)
                                    .onSubmit(submit)
                            }

                            Button(action: submit) {
                                Text(isSignUp ? "Hesap Oluştur" : "Giriş Yap")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 54)
                                    .background(canSubmit ? Color.accentColor : Color.accentColor.opacity(0.4), in: Capsule())
                            }
                            .disabled(!canSubmit)

                            if let error = authViewModel.errorMessage {
                                Text(error)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.red)
                                    .multilineTextAlignment(.center)
                                    .transition(.opacity)
                            }
                        }

                        // veya
                        HStack(spacing: 12) {
                            Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1)
                            Text("veya").font(.system(size: 13)).foregroundStyle(.secondary)
                            Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1)
                        }
                        .padding(.vertical, 24)

                        // Apple ve Google yan yana
                        HStack(spacing: 12) {
                            Button {
                                apple.start(authViewModel)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "apple.logo")
                                        .font(.system(size: 19, weight: .medium))
                                    Text("Apple")
                                }
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color(.systemBackground))
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(Color.primary, in: Capsule())
                            }
                            .accessibilityLabel("Apple ile giriş yap")

                            Button {
                                authViewModel.signInWithGoogle()
                            } label: {
                                HStack(spacing: 8) {
                                    Image("GoogleLogo")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 19, height: 19)
                                    Text("Google")
                                }
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular.interactive(), in: .capsule)
                            .accessibilityLabel("Google ile giriş yap")
                        }

                        if !isSignUp {
                            Button("Şifremi unuttum") { authViewModel.sendPasswordReset(trimmed) }
                                .font(.system(size: 15, weight: .medium))
                                .padding(.top, 20)
                        }

                        // Misafir
                        Button {
                            authViewModel.continueAsGuest()
                        } label: {
                            Text("Misafir olarak devam et")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 12)

                        HStack(spacing: 4) {
                            Text("Devam ederek")
                            NavigationLink("Koşullar") { TermsOfUseView() }
                            Text("ve")
                            NavigationLink("Gizlilik") { PrivacyPolicyView() }
                            Text("metnini kabul edersin.")
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .padding(.bottom, 8)
                    }
                    .padding(.horizontal, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollBounceBehavior(.basedOnSize)
            }
            .animation(.easeInOut(duration: 0.2), value: authViewModel.errorMessage)
            .overlay {
                if authViewModel.isLoading {
                    ZStack {
                        Color.black.opacity(0.15).ignoresSafeArea()
                        ProgressView()
                            .controlSize(.large)
                            .padding(28)
                            .glassEffect(in: .rect(cornerRadius: 24))
                    }
                }
            }
        }
    }

    private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(.system(size: 17))
            .padding(.horizontal, 20)
            .frame(height: 54)
            .glassEffect(in: .capsule)
    }

    private func submit() {
        guard canSubmit else { return }
        focused = nil
        if isSignUp { authViewModel.signUpWithEmail(trimmed, password: password) }
        else { authViewModel.signInWithEmail(trimmed, password: password) }
    }
}

// MARK: - Apple ile giriş (özel düğmeden)

/// SignInWithAppleButton yerine kendi düğmemizden Apple giriş penceresini açar; sonucu AuthViewModel'e iletir.
@MainActor
final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private weak var viewModel: AuthViewModel?

    func start(_ viewModel: AuthViewModel) {
        self.viewModel = viewModel
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = viewModel.prepareAppleSignIn()
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        MainActor.assumeIsolated { viewModel?.handleAppleSignIn(result: .success(authorization)) }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        MainActor.assumeIsolated { viewModel?.handleAppleSignIn(result: .failure(error)) }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}
