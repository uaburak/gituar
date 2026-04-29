import SwiftUI
import FirebaseAuth

struct HomeView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    
    @State private var searchText: String = ""
    @State private var navigateToProfile = false

    var body: some View {
        Group {
            if !searchText.isEmpty {
                List(viewModel.songs, id: \.docId) { song in
                    NavigationLink(destination: SongDetailView(song: song)) {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.secondarySystemBackground))
                                    .frame(width: 42, height: 42)
                                Text(song.songName.prefix(1).uppercased())
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(song.songName)
                                    .font(.system(size: 15, weight: .medium))
                                    .lineLimit(1)
                                Text(song.artist)
                                    .font(.system(size: 13))
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
                .listStyle(.plain)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        
                        // 1. Favorites & Repertoire Cards (Big)
                        HStack(spacing: 16) {
                            NavigationLink(destination: FavoritesView()) {
                                HomeBigCard(title: "Favoriler", icon: "heart.fill", color: .red)
                            }
                            
                            NavigationLink(destination: RepertoireListView()) {
                                HomeBigCard(title: "Repertuarlarım", icon: "music.note.list", color: .blue)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        
                        // 2. Action Row (Small Cards - Equal Width, 12px spacing)
                        HStack(alignment: .top, spacing: 12) {
                            NavigationLink(destination: AllArtistsView()) {
                                HomeSmallCard(title: "Sanatçılar", icon: "person.2.fill")
                            }
                            
                            NavigationLink(destination: ExploreView()) {
                                HomeSmallCard(title: "Şarkılar", icon: "music.note.list")
                            }
                            
                            NavigationLink(destination: PopularChordsView()) {
                                HomeSmallCard(title: "Popüler", icon: "star.fill")
                            }
                            
                            NavigationLink(destination: DiscoverView()) {
                                HomeSmallCard(title: "Keşfet", icon: "safari.fill")
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // 3. Recently Played
                        HorizontalSongScroll(title: "Son Çalınanlar", songs: viewModel.recentlyPlayed)
                        
                        // 4. Popular Chords
                        HorizontalSongScroll(title: "Popüler Şarkılar", songs: viewModel.popularChords)
                        
                        // 5. New Arrivals
                        HorizontalSongScroll(title: "Yeni Eklenenler", songs: viewModel.newArrivals)
                        
                        // 6. Most Added
                        HorizontalSongScroll(title: "En Çok Eklenenler", songs: viewModel.mostAdded)
                    }
                    .padding(.bottom, 32)
                }
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("") // Keep title for scroll edge effects
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Şarkı, sanatçı veya akor ara...")
        .onChange(of: searchText) { _, newValue in
            viewModel.searchText = newValue
        }
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
                                    Circle().fill(Color.accentColor.opacity(0.1))
                                    Text(authViewModel.userInitials)
                                        .font(.system(size: 14, weight: .bold))
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
                                .fill(Color.accentColor.opacity(0.1))
                            Text(authViewModel.userInitials)
                                .font(.system(size: 14, weight: .bold))
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
            
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text("Hoş geldin, \(authViewModel.displayName)")
                        .font(.system(size: 16, weight: .bold))
                    Text("Bugün ne çalmak istersin?")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Components

struct MinimalSongCard: View {
    let song: Song

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 130, height: 80)

                Text(song.songName.prefix(1).uppercased())
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(song.songName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 130)
    }
}

struct HomeBigCard: View {
    let title: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)
            
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(16)
    }
}

struct HomeSmallCard: View {
    let title: String
    let icon: String
    
    @Environment(\.horizontalSizeClass) var sizeClass
    
    var body: some View {
        if sizeClass == .compact {
            // Portrait / Compact Layout: Text below, outside the icon box
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                        .frame(height: 56) // Reduced height from square
                    
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
            // Landscape / Tablet Layout: Icon and Text side-by-side inside the card
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
            .background(Color(.secondarySystemBackground))
            .cornerRadius(14)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Navigation Views

struct FavoritesView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @State private var searchText: String = ""
    
    var filtered: [Song] {
        if searchText.isEmpty { return viewModel.favoriteSongs }
        return viewModel.favoriteSongs.filter {
            $0.songName.turkeyNormalized.contains(searchText.turkeyNormalized) ||
            $0.artist.turkeyNormalized.contains(searchText.turkeyNormalized)
        }
    }
    
    var body: some View {
        Group {
            if viewModel.favoriteSongs.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "heart.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Henüz favori şarkınız yok.")
                        .font(.headline)
                    Text("Şarkı detay ekranından kalp ikonuna basarak favorilere ekleyebilirsiniz.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            } else {
                List(filtered, id: \.docId) { song in
                    NavigationLink(destination: SongDetailView(song: song)) {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.secondarySystemBackground))
                                    .frame(width: 42, height: 42)
                                Text(song.songName.prefix(1).uppercased())
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                            }
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text(song.songName)
                                    .font(.system(size: 15, weight: .medium))
                                    .lineLimit(1)
                                Text(song.artist)
                                    .font(.system(size: 13))
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
                .listStyle(.plain)
                .searchable(text: $searchText, prompt: "Favorilerimde ara...")
            }
        }
        .navigationTitle("Favorilerim")
    }
}

struct AllArtistsView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @State private var searchText: String = ""
    
    var filteredArtists: [String] {
        if searchText.isEmpty { return viewModel.artists }
        return viewModel.artists.filter { $0.turkeyNormalized.contains(searchText.turkeyNormalized) }
    }
    
    var body: some View {
        List(filteredArtists, id: \.self) { artist in
            NavigationLink(destination: ArtistDetailView(artist: artist)) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.secondarySystemBackground))
                            .frame(width: 42, height: 42)
                        Text(artist.prefix(1).uppercased())
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(artist)
                            .font(.system(size: 15, weight: .medium))
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
            NavigationLink(destination: SongDetailView(song: song)) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.secondarySystemBackground))
                            .frame(width: 42, height: 42)
                        Text(song.songName.prefix(1).uppercased())
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(song.songName)
                            .font(.system(size: 15, weight: .medium))
                            .lineLimit(1)
                        Text(song.artist)
                            .font(.system(size: 13))
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
        .listStyle(.plain)
        .navigationTitle("Popüler")
        .searchable(text: $searchText, prompt: "Popülerlerde ara...")
    }
}



struct ArtistDetailView: View {
    let artist: String
    @EnvironmentObject var viewModel: ChordViewModel

    var body: some View {
        List(viewModel.songsForArtist(artist), id: \.docId) { song in
            NavigationLink(destination: SongDetailView(song: song)) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(song.songName)
                        .font(.system(size: 15, weight: .medium))
                    Text(song.originalKey)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.plain)
        .navigationTitle(artist)
    }
}

// MARK: - Reusable Horizontal Scroll
struct HorizontalSongScroll: View {
    let title: String
    let songs: [Song]
    
    var body: some View {
        if !songs.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .padding(.horizontal, 20)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(songs, id: \.docId) { song in
                            NavigationLink(destination: SongDetailView(song: song)) {
                                MinimalSongCard(song: song)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }
}
