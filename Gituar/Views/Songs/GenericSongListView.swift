import SwiftUI
import Combine

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
