import SwiftUI

struct ExploreView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @State private var searchText: String = ""

    var filtered: [Song] {
        guard !searchText.isEmpty else { return viewModel.allSongs }
        return viewModel.allSongs.filter {
            $0.songName.turkeyNormalized.contains(searchText.turkeyNormalized) ||
            $0.artist.turkeyNormalized.contains(searchText.turkeyNormalized)
        }
    }

    var body: some View {
        List(filtered) { song in
            NavigationLink(destination: SongDetailView(song: song, playlist: filtered)) {
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
    }
}
