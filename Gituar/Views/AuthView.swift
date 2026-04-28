import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @EnvironmentObject var authViewModel: AuthViewModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo
            VStack(spacing: 12) {
                Image(systemName: "guitars")
                    .font(.system(size: 44, weight: .light))
                    .foregroundColor(.primary)

                Text("Gituar")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.primary)

                Text("Akor, repertuar, transpoz.")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Butonlar
            VStack(spacing: 10) {
                SignInWithAppleButton(.signIn) { request in
                    let nonce = authViewModel.prepareAppleSignIn()
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = nonce
                } onCompletion: { result in
                    authViewModel.handleAppleSignIn(result: result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .cornerRadius(12)

                Button(action: authViewModel.signInWithGoogle) {
                    HStack(spacing: 10) {
                        Text("G")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Color(red: 0.26, green: 0.52, blue: 0.96))
                        Text("Google ile Devam Et")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.separator), lineWidth: 1)
                    )
                    .cornerRadius(12)
                }

                Button(action: authViewModel.continueAsGuest) {
                    Text("Misafir olarak devam et")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 28)

            // Hata
            if let error = authViewModel.errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.top, 14)
                    .transition(.opacity)
            }

            Spacer().frame(height: 48)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .animation(.easeInOut(duration: 0.2), value: authViewModel.errorMessage)
        .overlay {
            if authViewModel.isLoading {
                Color(.systemBackground).opacity(0.7).ignoresSafeArea()
                ProgressView()
            }
        }
    }
}
