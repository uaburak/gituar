import SwiftUI
import FirebaseAuth

struct CompleteProfileView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var username: String = ""
    @State private var email: String = ""
    
    @State private var isCheckingUsername = false
    @State private var isUsernameAvailable: Bool? = nil
    @State private var isSaving = false
    @State private var errorMessage: String? = nil
    
    @State private var searchTask: Task<Void, Never>? = nil
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        if let urlString = authViewModel.currentUser?.photoURL?.absoluteString, let url = URL(string: urlString) {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(width: 80, height: 80)
                            .clipShape(Circle())
                            .shadow(radius: 5)
                        } else {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(size: 60))
                                .foregroundStyle(Color.accentColor)
                        }
                        
                        Text("Aramıza Hoş Geldin!")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)
                        Text("Devam etmeden önce profilini tamamlayalım.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 24)
                    
                    VStack(spacing: 16) {
                        formField(title: "Ad", text: $firstName, placeholder: "Örn: Burak")
                        formField(title: "Soyad", text: $lastName, placeholder: "Örn: Koç")
                        formField(title: "E-Posta (İsteğe Bağlı)", text: $email, placeholder: "Örn: burak@example.com")
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Kullanıcı Adı")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            HStack {
                                Text("@")
                                    .foregroundStyle(.secondary)
                                
                                TextField("kullanici_adi", text: $username)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .onChange(of: username) { _, newValue in
                                        checkUsername(newValue)
                                    }
                                
                                if isCheckingUsername {
                                    ProgressView().scaleEffect(0.8)
                                } else if let available = isUsernameAvailable {
                                    Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundStyle(available ? .green : .red)
                                }
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color(.separator), lineWidth: 1))
                            
                            if isUsernameAvailable == false {
                                Text("Bu kullanıcı adı daha önce alınmış.")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                    
                    Button {
                        completeProfile()
                    } label: {
                        Group {
                            if isSaving {
                                Text("Kaydediliyor...")
                            } else {
                                Text("Tamamla")
                            }
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(isFormValid ? Color.accentColor : Color.accentColor.opacity(0.5))
                        .clipShape(Capsule())
                    }
                    .disabled(!isFormValid || isSaving)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                }
                .padding(.bottom, 24)
            }
            .onAppear {
                if let firebaseUser = authViewModel.currentUser {
                    if let fullName = firebaseUser.displayName {
                        let parts = fullName.components(separatedBy: " ")
                        if parts.count > 1 {
                            firstName = parts.dropLast().joined(separator: " ")
                            lastName = parts.last ?? ""
                        } else {
                            firstName = fullName
                        }
                    }
                    if let userEmail = firebaseUser.email {
                        email = userEmail
                    }
                }
            }
        }
    }
    
    private func formField(title: LocalizedStringKey, text: Binding<String>, placeholder: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField(placeholder, text: text)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color(.separator), lineWidth: 1))
        }
    }
    
    private var isFormValid: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespaces).isEmpty &&
        username.count >= 3 &&
        isUsernameAvailable == true
    }
    
    private func checkUsername(_ value: String) {
        searchTask?.cancel()
        
        let cleaned = value.lowercased().filter { "abcdefghijklmnopqrstuvwxyz0123456789_".contains($0) }
        if cleaned != value {
            username = cleaned
        }
        
        isUsernameAvailable = nil
        
        if cleaned.count < 3 {
            isCheckingUsername = false
            return
        }
        
        isCheckingUsername = true
        
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            
            do {
                let taken = try await UserService.shared.isUsernameTaken(cleaned)
                isUsernameAvailable = !taken
                isCheckingUsername = false
            } catch {
                isCheckingUsername = false
            }
        }
    }
    
    private func completeProfile() {
        guard let firebaseUser = authViewModel.currentUser else { return }
        isSaving = true
        errorMessage = nil
        
        let newUser = UserProfile(
            id: firebaseUser.uid,
            uid: firebaseUser.uid,
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            lastName: lastName.trimmingCharacters(in: .whitespaces),
            username: username.lowercased(),
            email: email.trimmingCharacters(in: .whitespaces).isEmpty ? nil : email.trimmingCharacters(in: .whitespaces),
            photoUrl: firebaseUser.photoURL?.absoluteString,
            createdAt: Date()
        )
        
        Task {
            do {
                try await UserService.shared.saveUserProfile(newUser)
                
                await MainActor.run {
                    self.isSaving = false
                    authViewModel.isProfileComplete = true
                }
                
            } catch {
                await MainActor.run {
                    self.isSaving = false
                    self.errorMessage = "Profil kaydedilirken hata oluştu: \(error.localizedDescription)"
                }
            }
        }
    }
}
