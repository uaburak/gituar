import SwiftUI
import FirebaseAuth
import Combine

struct HomeView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    
    @State private var navigateToProfile = false

    var body: some View {
        VStack(spacing: 0) {
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
                                    subtitle: authViewModel.currentUser != nil ? "\(viewModel.userSongs(userId: authViewModel.currentUser!.uid).count) Kayıtlı" : "Giriş Yap",
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
                        
                        // Action Row (Small Cards)
                        HStack(alignment: .top, spacing: 12) {
                            NavigationLink(destination: AllArtistsView()) {
                                HomeSmallCard(title: "Sanatçılar", icon: "person.2.fill")
                            }
                            
                            NavigationLink(destination: ExploreView()) {
                                HomeSmallCard(title: "Tüm Şarkılar", icon: "music.note.list")
                            }
                            
                            NavigationLink(destination: PopularChordsView()) {
                                HomeSmallCard(title: "Popüler", icon: "flame.fill")
                            }
                            
                            NavigationLink(destination: DiscoverView()) {
                                HomeSmallCard(title: "Keşfet", icon: "globe")
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Listeler
                        VStack(alignment: .leading, spacing: 12) {

                                
                            let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
                            
                            LazyVGrid(columns: columns, spacing: 12) {
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
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.bottom, 40)
                    .padding(.top, 16)
            } // End of ScrollView
            
            // Fixed Bottom Ad Banner
            let bannerWidth = UIScreen.main.bounds.width
            AdBannerView(viewWidth: bannerWidth)
                .frame(width: bannerWidth, height: 60)
                .background(Color(.systemBackground))
        }
        .ignoresSafeArea(.all, edges: .bottom)
        .background(Color(.systemBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToProfile) {
            ProfileSettingsView()
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
        }
    }
}

// MARK: - Components

struct MinimalCategoryCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(in: .rect(cornerRadius: 20.0))
    }
}

struct HomeSmallCard: View {
    let title: String
    let icon: String
    
    @Environment(\.horizontalSizeClass) var sizeClass
    
    var body: some View {
        if sizeClass == .compact {
            VStack(spacing: 8) {
                ZStack {
                    Color.clear
                        .glassEffect(in: .rect(cornerRadius: 20.0))
                        .frame(height: 56)
                    
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundColor(.primary)
                }
                
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(.primary)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(in: .rect(cornerRadius: 20.0))
            .frame(maxWidth: .infinity)
        }
    }
}

struct MinimalListCard: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.primary)
                .frame(width: 24)
            
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassEffect(in: .rect(cornerRadius: 20.0))
    }
}

struct SongRowCard: View {
    let song: Song
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 48, height: 48)
                Text(song.songName.prefix(1).uppercased())
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(song.songName)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(song.artist)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(song.originalKey)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Navigation Views

struct GenericSongListView: View {
    let title: String
    let songs: [Song]
    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    private let searchPublisher = PassthroughSubject<String, Never>()
    
    var filtered: [Song] {
        if debouncedSearchText.isEmpty { return songs }
        let query = debouncedSearchText.turkeyNormalized
        return songs.filter {
            $0.songName.turkeyNormalized.contains(query) ||
            $0.artist.turkeyNormalized.contains(query)
        }
    }

    var body: some View {
        Group {
            if songs.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Bu listede henüz şarkı yok.")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            } else {
                List(filtered, id: \.docId) { song in
                    NavigationLink(destination: SongDetailView(song: song, playlist: filtered)) {
                        SongRowCard(song: song)
                    }
                }
                .listStyle(.plain)
                .searchable(text: $searchText, prompt: "Ara...")
                .onReceive(searchPublisher.debounce(for: .milliseconds(500), scheduler: RunLoop.main)) { newValue in
                    debouncedSearchText = newValue
                }
                .onChange(of: searchText) { _, newValue in
                    searchPublisher.send(newValue)
                }
            }
        }
        .navigationTitle(title)
    }
}

struct GenericRepertoireListView: View {
    let title: String
    let repertoires: [Repertoire]
    
    var body: some View {
        Group {
            if repertoires.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "music.mic")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Bu listede henüz repertuar yok.")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            } else {
                ScrollView(showsIndicators: false) {
                    let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
                    
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(repertoires) { repertoire in
                            NavigationLink(destination: RepertoireDetailView(repertoire: repertoire)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(repertoire.name)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.primary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    
                                    Text("\(repertoire.songIds.count) Şarkı")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .glassEffect(in: .rect(cornerRadius: 20.0))
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}


struct AllArtistsView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    private let searchPublisher = PassthroughSubject<String, Never>()
    
    var filteredArtists: [String] {
        if debouncedSearchText.isEmpty { return viewModel.artists }
        let query = debouncedSearchText.turkeyNormalized
        return viewModel.artists.filter { $0.turkeyNormalized.contains(query) }
    }
    
    var body: some View {
        List(filteredArtists, id: \.self) { artist in
            NavigationLink(destination: ArtistDetailView(artist: artist)) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemBackground))
                            .frame(width: 48, height: 48)
                        Text(artist.prefix(1).uppercased())
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(artist)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        Text("\(viewModel.songsForArtist(artist).count) Şarkı")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(.systemGray4))
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.plain)
        .navigationTitle("Sanatçılar")
        .searchable(text: $searchText, prompt: "Sanatçı ara...")
        .onReceive(searchPublisher.debounce(for: .milliseconds(500), scheduler: RunLoop.main)) { newValue in
            debouncedSearchText = newValue
        }
        .onChange(of: searchText) { _, newValue in
            searchPublisher.send(newValue)
        }
    }
}

struct PopularChordsView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @State private var searchText: String = ""
    
    var filtered: [Song] {
        if searchText.isEmpty { return viewModel.popularChords }
        return viewModel.popularChords.filter {
            $0.songName.turkeyNormalized.contains(searchText.turkeyNormalized) ||
            $0.artist.turkeyNormalized.contains(searchText.turkeyNormalized)
        }
    }
    
    var body: some View {
        List(filtered, id: \.docId) { song in
            NavigationLink(destination: SongDetailView(song: song, playlist: filtered)) {
                SongRowCard(song: song)
            }
        }
        .listStyle(.plain)
        .navigationTitle("Popüler")
        .searchable(text: $searchText, prompt: "Popülerlerde ara...")
    }
}

struct ArtistDetailView: View {
    let artist: String
    @EnvironmentObject var viewModel: ChordViewModel

    var body: some View {
        let songs = viewModel.songsForArtist(artist)
        List(songs, id: \.docId) { song in
            NavigationLink(destination: SongDetailView(song: song, playlist: songs)) {
                SongRowCard(song: song)
            }
        }
        .listStyle(.plain)
        .navigationTitle(artist)
    }
}
