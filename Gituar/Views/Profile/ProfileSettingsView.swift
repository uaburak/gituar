import SwiftUI
import Foundation
import FirebaseAuth

struct ProfileSettingsView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var viewModel: ChordViewModel
    @ObservedObject private var proManager = ProManager.shared
    @State private var showingDeleteAlert = false
    @State private var isDeletingAccount = false
    @State private var showingReauthAlert = false
    @State private var deleteErrorMessage: String?
    @AppStorage("appTheme") private var appTheme = "system"


    private var initialsAvatar: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.12))
            Text(authViewModel.userInitials)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.accentColor)
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
            List {
                // Profil: ad soyad ve kullanıcı adı
                Section {
                    HStack(spacing: 12) {
                        Group {
                            if let photoURL = authViewModel.currentUser?.photoURL {
                                AsyncImage(url: photoURL) { phase in
                                    if case .success(let image) = phase {
                                        image.resizable().scaledToFill()
                                    } else {
                                        initialsAvatar
                                    }
                                }
                            } else {
                                initialsAvatar
                            }
                        }
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(authViewModel.displayName)
                                .font(.system(size: 17, weight: .semibold))
                            if let username = authViewModel.userProfile?.username {
                                Text("@\(username)")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Ayarlar: her konu kendi ekranında açılır
                Section(header: Text("Ayarlar")) {
                    NavigationLink(destination: ProView()) {
                        HStack {
                            Label("Gituar Pro", systemImage: "sparkles")
                            Spacer()
                            if proManager.isPro {
                                Text("Aktif").foregroundColor(.secondary)
                            }
                        }
                    }
                    Picker(selection: $appTheme) {
                        Text("Sistem").tag("system")
                        Text("Açık").tag("light")
                        Text("Koyu").tag("dark")
                    } label: {
                        Label("Tema", systemImage: "circle.lefthalf.filled")
                    }
                    NavigationLink(destination: SongPageSettingsView()) {
                        Label("Şarkı Sayfası", systemImage: "music.note.list")
                    }
                    NavigationLink(destination: ChordSettingsView()) {
                        Label("Akorlar", systemImage: "guitars")
                    }
                    NavigationLink(destination: OfflineSettingsView()) {
                        Label("Çevrimdışı", systemImage: "icloud.and.arrow.down")
                    }
                    if !viewModel.blockedUserIDs.isEmpty {
                        NavigationLink(destination: BlockedUsersView()) {
                            Label("Engellenen Kullanıcılar", systemImage: "person.crop.circle.badge.xmark")
                        }
                    }
                }

                // Yönetim (yalnızca yöneticiler)
                if authViewModel.isAdmin {
                    Section(header: Text("Yönetim")) {
                        NavigationLink(destination: PendingApprovalListView()) {
                            Label("Onay Bekleyenler", systemImage: "checkmark.seal")
                        }
                        NavigationLink(destination: ReportsListView()) {
                            Label("Şikayetler", systemImage: "exclamationmark.shield")
                        }
                        NavigationLink(destination: ProMembersView()) {
                            Label("Pro Üyeler", systemImage: "crown")
                        }
                    }
                }

                // Yasal ve uygulama
                Section(header: Text("Yasal")) {
                    NavigationLink(destination: LegalContactView()) {
                        Label("İletişim ve Yasal Bilgiler", systemImage: "info.circle")
                    }
                    if let review = URL(string: "itms-apps://itunes.apple.com/app/id6764865998?action=write-review") {
                        Link(destination: review) {
                            Label {
                                Text("Uygulamayı Değerlendir").foregroundColor(.primary)
                            } icon: {
                                Image(systemName: "star").foregroundColor(.accentColor)
                            }
                        }
                    }
                    if let appURL = URL(string: "https://apps.apple.com/tr/app/id6764865998") {
                        ShareLink(item: appURL) {
                            Label {
                                Text("Arkadaşına Öner").foregroundColor(.primary)
                            } icon: {
                                Image(systemName: "square.and.arrow.up").foregroundColor(.accentColor)
                            }
                        }
                    }
                    HStack {
                        Label("Sürüm", systemImage: "number")
                        Spacer()
                        Text(appVersion).foregroundColor(.secondary)
                    }
                }

                // Hesap — listenin en altında, diğer satırlar gibi
                Section {
                    if authViewModel.isGuestMode {
                        // Misafirin çıkış yapacağı ya da sileceği bir hesabı yok — giriş ekranına götür
                        Button {
                            authViewModel.signOut()
                        } label: {
                            Label("Giriş Yap", systemImage: "person.crop.circle.badge.plus")
                                .foregroundColor(.accentColor)
                        }
                    } else {
                        Button(role: .destructive) {
                            authViewModel.signOut()
                        } label: {
                            Label("Çıkış Yap", systemImage: "rectangle.portrait.and.arrow.right")
                                .foregroundColor(.red)
                        }
                        Button(role: .destructive) {
                            showingDeleteAlert = true
                        } label: {
                            HStack {
                                Label("Hesabımı Kalıcı Olarak Sil", systemImage: "trash")
                                    .foregroundColor(.red)
                                if isDeletingAccount {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isDeletingAccount)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollEdgeEffectStyle(.soft)
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

// MARK: - Ayar ekranları

struct SongPageSettingsView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @AppStorage("songFontSize") private var songFontSize: Double = 14
    @AppStorage("hideChords") private var hideChords = false
    @AppStorage("autoScrollSpeed") private var autoScrollSpeed: Double = 14.0
    @AppStorage("keepScreenAwake") private var keepScreenAwake = true
    @State private var showingClearRecent = false

    var body: some View {
        List {
            Section {
                Stepper(value: $songFontSize, in: 11...24, step: 1) {
                    HStack {
                        Label("Yazı Boyutu", systemImage: "textformat.size")
                        Spacer()
                        Text("\(Int(songFontSize))").foregroundColor(.secondary).monospacedDigit()
                    }
                }
                Toggle(isOn: $hideChords) {
                    Label("Akorları Gizle", systemImage: "eye.slash")
                }
                Picker(selection: $autoScrollSpeed) {
                    Text("Çok Yavaş").tag(6.0)
                    Text("Yavaş").tag(10.0)
                    Text("Normal").tag(14.0)
                    Text("Hızlı").tag(20.0)
                    Text("Çok Hızlı").tag(28.0)
                } label: {
                    Label("Kaydırma Hızı", systemImage: "arrow.down.to.line")
                }
                Toggle(isOn: $keepScreenAwake) {
                    Label("Ekranı Açık Tut", systemImage: "sun.max")
                }
            }
            Section {
                Button(role: .destructive) {
                    showingClearRecent = true
                } label: {
                    Label("Son Çaldıklarımı Temizle", systemImage: "clock.arrow.circlepath")
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Şarkı Sayfası")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Son çaldıkların silinsin mi?", isPresented: $showingClearRecent) {
            Button("Temizle", role: .destructive) { viewModel.clearRecentlyPlayed() }
            Button("Vazgeç", role: .cancel) { }
        }
    }
}

struct ChordSettingsView: View {
    @AppStorage("chordSoundOnTap") private var chordSoundOnTap = true
    @AppStorage("haptics") private var haptics = true
    @State private var quality = ""
    @State private var selected: String?

    private let roots = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
    private let qualities: [(String, String)] = [("", "Majör"), ("m", "Minör"), ("7", "7"), ("m7", "m7"), ("maj7", "maj7"),
                                                 ("sus2", "sus2"), ("sus4", "sus4"), ("add9", "add9"), ("dim", "dim"), ("aug", "aug")]

    var body: some View {
        List {
            Section {
                Toggle(isOn: $chordSoundOnTap) {
                    Label("Dokununca Sesi Çal", systemImage: "speaker.wave.2")
                }
                Toggle(isOn: $haptics) {
                    Label("Titreşim", systemImage: "iphone.radiowaves.left.and.right")
                }
            }

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(qualities, id: \.0) { q in
                            Button {
                                withAnimation(.snappy) { quality = q.0; selected = nil }
                            } label: {
                                Text(q.1)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(quality == q.0 ? .white : .primary)
                                    .padding(.horizontal, 14)
                                    .frame(height: 34)
                                    .background(quality == q.0 ? Color.accentColor : Color(.tertiarySystemFill), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 14) {
                    ForEach(roots, id: \.self) { root in
                        let name = root + quality
                        let shape = ChordShapes.shapes(for: name).first
                        Button {
                            guard let shape else { return }
                            selected = name
                            if haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                            ChordPlayer.shared.play(frets: shape.frets, capo: 0)
                        } label: {
                            VStack(spacing: 4) {
                                if let shape {
                                    ChordDiagramView(shape: shape)
                                        .frame(width: 80, height: 96)
                                } else {
                                    Color.clear.frame(width: 80, height: 96)
                                }
                                Text(name)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(selected == name ? .accentColor : .primary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(selected == name ? Color.accentColor.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Text("Akorlar")
            }
        }
        .navigationTitle("Akorlar")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct OfflineSettingsView: View {
    var body: some View {
        List { OfflineSettingsSection() }
            .navigationTitle("Çevrimdışı")
            .navigationBarTitleDisplayMode(.inline)
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
