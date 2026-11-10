import SwiftUI
import FirebaseFirestore

/// Herkese açık kullanıcı profili (web'deki /kullanici/{kullanıcı adı}/ ile aynı): kişinin herkesle paylaştığı
/// repertuarlar ve yayındaki şarkıları; paylaş düğmesi web adresini paylaşır.
struct PublicProfileView: View {
    let ownerId: String
    @State var username: String?
    @EnvironmentObject var viewModel: ChordViewModel

    @State private var songs: [Song] = []
    @State private var isLoadingSongs = true
    @State private var songsError: String?
    @State private var showBlockAlert = false
    @State private var showBlocked = false

    init(ownerId: String, username: String? = nil) {
        self.ownerId = ownerId
        _username = State(initialValue: username)
    }

    private var repertoires: [Repertoire] {
        viewModel.publicRepertoires.filter { $0.ownerId == ownerId }
    }

    private var webURL: URL? {
        guard let username, !username.isEmpty,
              let encoded = username.lowercased().addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "https://gituar.com/kullanici/\(encoded)/")
    }

    private var isMe: Bool { viewModel.currentUserId == ownerId }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Color.accentColor.opacity(0.15))
                        Text((username ?? "?").prefix(1).uppercased())
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }
                    .frame(width: 60, height: 60)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(username.map { "@\($0)" } ?? "Kullanıcı")
                            .font(.system(size: 18, weight: .bold))
                        Text(summary)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            if !repertoires.isEmpty {
                Section("Repertuarlar") {
                    ForEach(repertoires) { rep in
                        NavigationLink(destination: RepertoireDetailView(repertoire: rep)) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(rep.name).font(.system(size: 15, weight: .semibold))
                                Text("\(rep.songIds.count) Şarkı").font(.system(size: 13)).foregroundColor(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }

            Section("Paylaştığı şarkılar") {
                if isLoadingSongs && songs.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if let songsError, songs.isEmpty {
                    Text(songsError).font(.system(size: 13)).foregroundColor(.secondary)
                } else if songs.isEmpty {
                    Text("Henüz yayında şarkısı yok.").font(.system(size: 13)).foregroundColor(.secondary)
                } else {
                    ForEach(songs, id: \.docId) { song in
                        NavigationLink(destination: SongDetailView(song: song, playlist: songs)) {
                            SongRowCard(song: song)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(username.map { "@\($0)" } ?? "Profil")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let url = webURL {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Profili paylaş")
                }
            }
            if !isMe, viewModel.currentUserId != nil {
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if viewModel.blockedUserIDs.contains(ownerId) {
                            Button("Engeli Kaldır") { viewModel.unblockUser(ownerId: ownerId) }
                        } else {
                            Button("Engelle", role: .destructive) { showBlockAlert = true }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Diğer")
                }
            }
        }
        .alert("Kullanıcıyı Engelle", isPresented: $showBlockAlert) {
            Button("Evet, Engelle", role: .destructive) {
                viewModel.blockUser(ownerId: ownerId)
                showBlocked = true
            }
            Button("İptal", role: .cancel) {}
        } message: {
            Text("Engellediğin kullanıcının içeriklerini görmeyeceksin.")
        }
        .alert("Kullanıcı Engellendi", isPresented: $showBlocked) {
            Button("Tamam", role: .cancel) {}
        }
        .task { await load() }
    }

    private var summary: String {
        var parts: [String] = []
        if !repertoires.isEmpty { parts.append("\(repertoires.count) repertuar") }
        if !songs.isEmpty { parts.append("\(songs.count) şarkı") }
        return parts.isEmpty ? "Gituar kullanıcısı" : parts.joined(separator: " · ") + " paylaşıyor"
    }

    private func load() async {
        if username == nil {
            // Herkese açık repertuarlarda kullanıcı adı yazılı; yoksa profil belgesinden (girişliyken okunur)
            if let fromRep = repertoires.compactMap(\.ownerUsername).first {
                username = fromRep
            } else if let profile = try? await UserService.shared.getPublicUserProfile(uid: ownerId) {
                username = profile.username
            }
        }
        isLoadingSongs = true
        defer { isLoadingSongs = false }
        do {
            // Sunucu ?owner süzgecini bilmiyorsa bile yalnızca bu kişinin şarkıları kalsın
            songs = try await GituarAPI.shared.songs(owner: ownerId).filter { $0.ownerId == ownerId }
            songsError = nil
        } catch is CancellationError {
        } catch {
            songsError = error.localizedDescription
        }
    }
}
