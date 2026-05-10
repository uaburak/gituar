import SwiftUI

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
