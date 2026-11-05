import SwiftUI
import Combine

struct GenericSongListView: View {
    let title: String
    let songs: [Song]

    /// Eğer true ise, songs dizisi ChordsStorageManager'a bağımlıdır ve
    /// manager hazır değilken spinner gösterilir.
    var requiresStorageReady: Bool = false

    @EnvironmentObject var chordsManager: ChordsStorageManager
    @ObservedObject private var adMobManager = AdMobManager.shared
    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    private let searchPublisher = PassthroughSubject<String, Never>()

    var filtered: [Song] {
        SongSearch.filter(songs, query: debouncedSearchText)
    }

    var body: some View {
        Group {
            // Spinner: sadece bu liste Storage verisine bağımlıysa ve indirme bitmemişse göster
            if requiresStorageReady && (chordsManager.state == .idle || chordsManager.state == .downloading) {
                CatalogLoadingView()
            } else if songs.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Bu listede henüz şarkı yok.")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(filtered.enumerated()), id: \.element.docId) { index, song in
                        NavigationLink(destination: SongDetailView(song: song, playlist: filtered)) {
                            SongRowCard(song: song)
                        }
                        // Her 10 satırda bir yerel reklam (Plus'ta yok)
                        if AdPlacements.shouldShowNativeAd(afterRow: index, isAdFree: adMobManager.isAdFree) {
                            NativeAdRow()
                        }
                    }
                }
                .listStyle(.plain)
                .scrollEdgeEffectStyle(.soft)
                .overlay {
                    if filtered.isEmpty {
                        NoSearchResultsView(query: debouncedSearchText)
                    }
                }
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

