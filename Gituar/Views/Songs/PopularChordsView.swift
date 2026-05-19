import SwiftUI

struct PopularChordsView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @EnvironmentObject var chordsManager: ChordsStorageManager
    @State private var searchText: String = ""

    var filtered: [Song] {
        if searchText.isEmpty { return viewModel.popularChords }
        return viewModel.popularChords.filter {
            $0.songName.turkeyNormalized.contains(searchText.turkeyNormalized) ||
            $0.artist.turkeyNormalized.contains(searchText.turkeyNormalized)
        }
    }

    var body: some View {
        Group {
            if chordsManager.state == .idle || chordsManager.state == .downloading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(.secondary)
                    Text("Popüler şarkılar yükleniyor…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered, id: \.docId) { song in
                    NavigationLink(destination: SongDetailView(song: song, playlist: filtered)) {
                        SongRowCard(song: song)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Popüler")
        .searchable(text: $searchText, prompt: "Popülerlerde ara...")
    }
}

