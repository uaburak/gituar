import SwiftUI
import FirebaseAuth
import Combine

struct HomeView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var chordsManager: ChordsStorageManager

    @State private var navigateToProfile = false
    @State private var navigateToPlus = false
    @ObservedObject private var plus = PlusManager.shared

    // Arama — AllArtistsView ile aynı kurulum (.searchable + 500 ms debounce)
    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    private let searchPublisher = PassthroughSubject<String, Never>()
    @State private var searchResults = HomeSearchResults()

    /// Sorgu ya da katalog değiştiğinde aramayı yeniden başlatır (öncekini iptal ederek).
    private struct SearchTrigger: Equatable {
        let query: String
        let songsVersion: Int
    }

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    private var trimmedDebouncedQuery: String {
        debouncedSearchText.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        Group {
            if trimmedQuery.isEmpty {
                homeContent
            } else {
                searchResultsBody
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea(.all, edges: .bottom))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Şarkı veya sanatçı ara...")
        .onReceive(searchPublisher.debounce(for: .milliseconds(500), scheduler: RunLoop.main)) { newValue in
            debouncedSearchText = newValue
        }
        .onChange(of: searchText) { _, newValue in
            searchPublisher.send(newValue)
        }
        .task(id: SearchTrigger(query: trimmedDebouncedQuery, songsVersion: viewModel.visibleSongsVersion)) {
            await updateSearchResults()
        }
        .navigationDestination(isPresented: $navigateToProfile) {
            ProfileSettingsView()
        }
        .navigationDestination(isPresented: $navigateToPlus) {
            PlusView()
        }
        // gituar://song/<id> bağlantısıyla gelen şarkı
        .navigationDestination(item: $viewModel.deepLinkedSong) { song in
            SongDetailView(song: song)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                ZStack {
                    if let photoURL = authViewModel.currentUser?.photoURL {
                        AsyncImage(url: photoURL) { phase in
                            switch phase {
                            case .empty:
                                Circle().fill(Color(.systemGray5))
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                ZStack {
                                    Circle().fill(Color.accentColor.opacity(0.15))
                                    Text(authViewModel.userInitials)
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(.accentColor)
                                }
                            @unknown default:
                                Circle().fill(Color(.systemGray5))
                            }
                        }
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                    } else {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.15))
                            Text(authViewModel.userInitials)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.accentColor)
                        }
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                    }
                }
                .onTapGesture {
                    let impactMed = UIImpactFeedbackGenerator(style: .light)
                    impactMed.impactOccurred()
                    navigateToProfile = true
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Profil")
                .accessibilityAddTraits(.isButton)
            }

            ToolbarSpacer(.fixed, placement: .topBarLeading)

            ToolbarItem(placement: .topBarLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hoş geldin, \(authViewModel.displayName.split(separator: " ").first ?? "")")
                        .font(.system(size: 16, weight: .bold))
                    Text("Bugün ne çalıyoruz?")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .sharedBackgroundVisibility(.hidden)

            // Ücretli sürüme teşvik: abone olmayanlara sağ üstte "Pro" düğmesi
            ToolbarItem(placement: .topBarTrailing) {
                if !plus.isPlus {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        navigateToPlus = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "crown.fill")
                            Text("Pro")
                        }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(colors: [.orange, .pink], startPoint: .leading, endPoint: .trailing),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Pro'ya geç")
                }
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    // MARK: - Ana sayfa içeriği

    private var homeContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {

                // Editor's Choice Banner
                if !viewModel.editorRepertoires.isEmpty {
                    NavigationLink(destination: GenericRepertoireListView(title: "Editörün Seçimleri", repertoires: viewModel.editorRepertoires)) {
                        VStack(alignment: .leading, spacing: 14) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.yellow)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Editörün Seçimleri")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                Text("\(viewModel.editorRepertoires.count) Özel Liste")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(
                            Image("EditorChoiceImage")
                                .resizable()
                                .scaledToFill()
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .glassEffect(in: .rect(cornerRadius: 20.0))
                    }
                    .padding(.horizontal, 20)
                }

                // Hero Section
                HStack(spacing: 12) {
                    NavigationLink(destination: MySongsView()) {
                        MinimalCategoryCard(
                            title: "Şarkılarım",
                            subtitle: authViewModel.currentUser.map { "\(viewModel.userSongs(userId: $0.uid).count) Kayıtlı" } ?? "Giriş Yap",
                            icon: "music.quarternote.3",
                            color: .indigo
                        )
                    }

                    NavigationLink(destination: RepertoireListView()) {
                        MinimalCategoryCard(
                            title: "Repertuarlarım",
                            subtitle: "Listeler",
                            icon: "music.mic",
                            color: .orange
                        )
                    }
                }
                .padding(.horizontal, 20)

                // Listeler
                VStack(alignment: .leading, spacing: 12) {
                    let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

                    LazyVGrid(columns: columns, spacing: 12) {
                        NavigationLink(destination: AllArtistsView()) {
                            MinimalListCard(title: "Sanatçılar", icon: "person.2.fill")
                        }
                        NavigationLink(destination: GenericSongListView(title: "Son Çalınanlar", songs: viewModel.recentlyPlayed)) {
                            MinimalListCard(title: "Son Çalınanlar", icon: "clock.fill")
                        }
                        NavigationLink(destination: GenericSongListView(title: "Yeni Eklenenler", songs: viewModel.newArrivals)) {
                            MinimalListCard(title: "Yeni Eklenenler", icon: "arrow.down.circle.fill")
                        }
                        NavigationLink(destination: GenericSongListView(title: "En Çok Eklenenler", songs: viewModel.mostAdded)) {
                            MinimalListCard(title: "Çok Eklenenler", icon: "star.fill")
                        }

                        if authViewModel.isAdmin {
                            NavigationLink(destination: PendingApprovalListView()) {
                                MinimalListCard(title: "Onay Bekleyenler", icon: "checkmark.seal.fill")
                            }
                            NavigationLink(destination: ReportsListView()) {
                                MinimalListCard(title: "Şikayetler", icon: "exclamationmark.shield.fill")
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                AdNativeView()
                    .padding(.horizontal, 20)
            }
            .padding(.bottom, 40)
            .padding(.top, 16)
        }
        .scrollEdgeEffectStyle(.soft)
    }

    // MARK: - Arama sonuçları (şarkı + sanatçı)

    /// Gösterilen sonuçlar yazılan sorguya ait mi? (Debounce/hesaplama sürerken eski sonuçlar kalır,
    /// "sonuç yok" ekranı ancak güncel sorgu gerçekten boş dönünce çıkar.)
    private var resultsAreCurrent: Bool {
        searchResults.query == trimmedQuery
    }

    @ViewBuilder
    private var searchResultsBody: some View {
        if chordsManager.state == .idle || chordsManager.state == .downloading {
            CatalogLoadingView()
        } else if resultsAreCurrent && searchResults.isEmpty {
            NoSearchResultsView(query: trimmedQuery)
        } else {
            List {
                if !searchResults.artists.isEmpty {
                    Section("Sanatçılar") {
                        ForEach(searchResults.artists, id: \.self) { artist in
                            NavigationLink(destination: ArtistDetailView(artist: artist)) {
                                ArtistRowCard(artist: artist, songCount: viewModel.artistSongCount[artist] ?? 0)
                            }
                        }
                    }
                }
                if !searchResults.songs.isEmpty {
                    Section("Şarkılar") {
                        ForEach(searchResults.songs, id: \.docId) { song in
                            NavigationLink(destination: SongDetailView(song: song, playlist: searchResults.songs)) {
                                SongRowCard(song: song)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollEdgeEffectStyle(.soft)
        }
    }

    private func updateSearchResults() async {
        let query = trimmedDebouncedQuery
        guard !query.isEmpty else {
            searchResults = HomeSearchResults()
            return
        }
        let songs = viewModel.visibleSongs
        let artists = viewModel.artists
        // 13 bin+ şarkı üzerinde normalize + filtre — ana iş parçacığını bloklamamak için arka planda
        let results = await Task.detached(priority: .userInitiated) {
            let normalized = query.turkeyNormalized
            return HomeSearchResults(
                query: query,
                artists: artists.filter { $0.turkeyNormalized.contains(normalized) },
                songs: SongSearch.filter(songs, query: query, ranked: true)
            )
        }.value
        guard !Task.isCancelled else { return }
        searchResults = results
    }
}

/// Ana sayfa aramasının tek seferde hesaplanan sonuçları.
private struct HomeSearchResults: Sendable {
    var query: String = ""
    var artists: [String] = []
    var songs: [Song] = []

    var isEmpty: Bool { artists.isEmpty && songs.isEmpty }
}
