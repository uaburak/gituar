import SwiftUI
import Foundation
import FirebaseAuth

struct ProfileSettingsView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var viewModel: ChordViewModel
    @ObservedObject private var plusManager = PlusManager.shared
    @State private var showingDeleteAlert = false
    @State private var isDeletingAccount = false
    @State private var showingReauthAlert = false
    @State private var deleteErrorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            List {
                // Profil Bilgisi
                Section {
                    HStack(spacing: 16) {
                        if let photoURL = authViewModel.currentUser?.photoURL {
                            AsyncImage(url: photoURL) { phase in
                                switch phase {
                                case .empty:
                                    ZStack {
                                        Circle().fill(Color(.systemGray5))
                                        ProgressView()
                                    }
                                case .success(let image):
                                    image.resizable().scaledToFill()
                                case .failure:
                                    ZStack {
                                        Circle().fill(Color.accentColor.opacity(0.1))
                                        Text(authViewModel.userInitials)
                                            .font(.system(size: 24, weight: .bold))
                                            .foregroundColor(.accentColor)
                                    }
                                @unknown default:
                                    Circle().fill(Color(.systemGray5))
                                }
                            }
                            .frame(width: 72, height: 72)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.accentColor.opacity(0.2), lineWidth: 1))
                        } else {
                            ZStack {
                                Circle().fill(Color.accentColor.opacity(0.1))
                                Text(authViewModel.userInitials)
                                    .font(.system(size: 26, weight: .bold))
                                    .foregroundColor(.accentColor)
                            }
                            .frame(width: 72, height: 72)
                            .overlay(Circle().stroke(Color.accentColor.opacity(0.2), lineWidth: 1))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(authViewModel.displayName)
                                .font(.title3).fontWeight(.bold)
                            
                            if let username = authViewModel.userProfile?.username {
                                Text("@\(username)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.accentColor)
                            }
                            
                            if !authViewModel.userEmail.isEmpty && authViewModel.userEmail != "Misafir Kullanıcı" {
                                Text(authViewModel.userEmail)
                                    .font(.footnote).foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section(header: Text("Gituar Pro")) {
                    NavigationLink(destination: PlusView()) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(plusManager.isPlus ? "Gituar Pro · Aktif" : "Gituar Pro")
                                    .foregroundColor(.primary)
                                Text(plusManager.isPlus ? "Reklamsız kullanım açık" : "Reklamsız kullan · aylık 99 TL")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "sparkles")
                                .foregroundColor(.accentColor)
                        }
                    }
                }

                Section(header: Text("Hakkında")) {
                    NavigationLink(destination: LegalContactView()) {
                        Label("İletişim ve Yasal Bilgiler", systemImage: "info.circle.fill")
                            .foregroundColor(.primary)
                    }
                }

                // Gizlilik — engellenen biri varsa göster
                if !viewModel.blockedUserIDs.isEmpty {
                    Section(header: Text("Gizlilik")) {
                        NavigationLink(destination: BlockedUsersView()) {
                            Label(
                                "Engellenen Kullanıcılar (\(viewModel.blockedUserIDs.count))",
                                systemImage: "person.crop.circle.badge.xmark"
                            )
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollEdgeEffectStyle(.soft)

            // Glass Butonlar — List'in TAMAMEN DIŞINDA
            VStack(spacing: 12) {
                if authViewModel.isGuestMode {
                    // Misafirin çıkış yapacağı ya da sileceği bir hesabı yok — giriş ekranına götür
                    Button {
                        authViewModel.signOut()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.crop.circle.badge.plus")
                            Text("Giriş Yap")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .glassEffect(in: .rect(cornerRadius: 18.0))
                    }
                } else {
                    Button {
                        authViewModel.signOut()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Çıkış Yap")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .glassEffect(in: .rect(cornerRadius: 18.0))
                    }

                    Button {
                        showingDeleteAlert = true
                    } label: {
                        HStack(spacing: 8) {
                            if isDeletingAccount {
                                ProgressView().tint(.red)
                            } else {
                                Image(systemName: "trash")
                                Text("Hesabımı Kalıcı Olarak Sil")
                                    .fontWeight(.semibold)
                            }
                        }
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .glassEffect(in: .rect(cornerRadius: 18.0))
                    }
                    .disabled(isDeletingAccount)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .navigationTitle("Profil")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Hesabı Sil", isPresented: $showingDeleteAlert) {
            Button("İptal", role: .cancel) { }
            Button("Evet, Hesabımı Sil", role: .destructive) {
                Task {
                    isDeletingAccount = true
                    do {
                        try await UserService.shared.deleteAccount()
                        authViewModel.signOut()
                    } catch UserService.AccountDeletionError.requiresRecentLogin {
                        showingReauthAlert = true
                    } catch {
                        print("Error deleting account: \(error)")
                        deleteErrorMessage = error.localizedDescription
                    }
                    isDeletingAccount = false
                }
            }
        } message: {
            Text("Hesabınızı silmek istediğinize emin misiniz? Bu işlem geri alınamaz ve tüm verileriniz kalıcı olarak silinir.")
        }
        .alert("Yeniden Giriş Gerekli", isPresented: $showingReauthAlert) {
            Button("Çıkış Yap") { authViewModel.signOut() }
            Button("Vazgeç", role: .cancel) { }
        } message: {
            Text("Güvenlik nedeniyle hesabınızı silmeden önce yeniden giriş yapmanız gerekiyor. Çıkış yapıp tekrar giriş yaptıktan sonra hesabınızı silebilirsiniz.")
        }
        .alert("Hesap Silinemedi", isPresented: Binding(
            get: { deleteErrorMessage != nil },
            set: { if !$0 { deleteErrorMessage = nil } }
        )) {
            Button("Tamam", role: .cancel) { }
        } message: {
            Text("Hesabınız silinirken bir hata oluştu. İnternet bağlantınızı kontrol edip tekrar deneyin.\n\n\(deleteErrorMessage ?? "")")
        }
    }
}

// MARK: - Blocked Users Feature

struct BlockedUsersView: View {
    @EnvironmentObject var viewModel: ChordViewModel

    var body: some View {
        List {
            if viewModel.blockedUserIDs.isEmpty {
                Text("Engellenen kullanıcı bulunmuyor.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(viewModel.blockedUserIDs, id: \.self) { uid in
                    BlockedUserRow(uid: uid)
                }
            }
        }
        .scrollEdgeEffectStyle(.soft)
        .navigationTitle("Engellenen Kullanıcılar")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct BlockedUserRow: View {
    let uid: String
    @EnvironmentObject var viewModel: ChordViewModel
    @State private var username: String? = nil

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(username ?? "Yükleniyor...")
                    .font(.system(size: 15, weight: .medium))
                Text(uid)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("Engeli Kaldır") {
                withAnimation {
                    viewModel.unblockUser(ownerId: uid)
                }
            }
            .foregroundColor(.blue)
            .font(.system(size: 13, weight: .semibold))
        }
        .task {
            do {
                if let profile = try await UserService.shared.getPublicUserProfile(uid: uid) {
                    await MainActor.run { self.username = "@\(profile.username)" }
                } else {
                    await MainActor.run { self.username = "Bilinmeyen Kullanıcı" }
                }
            } catch {
                await MainActor.run { self.username = "Bilinmeyen Kullanıcı" }
            }
        }
    }
}
