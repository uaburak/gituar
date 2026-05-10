import SwiftUI

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
