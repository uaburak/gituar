import SwiftUI
import Combine

struct ExploreView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @State private var searchText: String = ""

    var displaySongs: [Song] {
        if searchText.isEmpty {
            return viewModel.allSongs
        } else {
            return viewModel.songs
        }
    }

    var body: some View {
        List(displaySongs) { song in
            NavigationLink(destination: SongDetailView(song: song, playlist: displaySongs)) {
                HStack(spacing: 14) {
                    // Harf avatar
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
        .navigationTitle("Tüm Şarkılar")
        .searchable(text: $searchText, prompt: "Ara")
        .onChange(of: searchText) { _, newValue in
            viewModel.searchText = newValue
        }
    }
}
