import SwiftUI

struct ArtistDetailView: View {
    let artist: String
    @EnvironmentObject var viewModel: ChordViewModel
    @EnvironmentObject var chordsManager: ChordsStorageManager

    // Kaynak her zaman viewModel — Storage + user_chords zaten merge edilmiş durumda
    private var songs: [Song] { viewModel.songsForArtist(artist) }

    var body: some View {
        Group {
            switch chordsManager.state {
            case .idle, .downloading:
                CatalogLoadingView()

            default:
                if songs.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("Bu sanatçıya ait şarkı bulunamadı.")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(songs, id: \.docId) { song in
                        NavigationLink(destination: SongDetailView(song: song, playlist: songs)) {
                            SongRowCard(song: song)
                        }
                    }
                    .listStyle(.plain)
                    .scrollEdgeEffectStyle(.soft)
                }
            }
        }
        .navigationTitle(artist)
    }
}

