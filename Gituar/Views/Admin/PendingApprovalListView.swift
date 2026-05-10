import SwiftUI

struct PendingApprovalListView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @State private var searchText: String = ""
    
    var filtered: [Song] {
        if searchText.isEmpty { return viewModel.pendingSongs }
        return viewModel.pendingSongs.filter {
            $0.songName.turkeyNormalized.contains(searchText.turkeyNormalized) ||
            $0.artist.turkeyNormalized.contains(searchText.turkeyNormalized)
        }
    }

    var body: some View {
        Group {
            if viewModel.pendingSongs.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Bekleyen onay yok.")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Tüm şarkılar güncel.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                List(filtered, id: \.docId) { song in
                    NavigationLink(destination: SongApprovalDetailView(song: song, playlist: filtered)) {
                        SongRowCard(song: song)
                    }
                }
                .listStyle(.plain)
                .searchable(text: $searchText, prompt: "Bekleyenlerde ara...")
            }
        }
        .navigationTitle("Onay Bekleyenler")
    }
}
