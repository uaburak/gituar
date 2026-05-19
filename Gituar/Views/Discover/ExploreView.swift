import SwiftUI
import Combine

struct ExploreView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @EnvironmentObject var chordsManager: ChordsStorageManager
    @State private var searchText: String = ""

    // viewModel.visibleSongs: engelleme + onay filtresi uygulanmış güvenli liste
    var displaySongs: [Song] {
        guard !searchText.isEmpty else { return viewModel.visibleSongs }
        let query = searchText.turkeyNormalized
        return viewModel.visibleSongs.filter {
            $0.songName.turkeyNormalized.contains(query) ||
            $0.artist.turkeyNormalized.contains(query)
        }
    }

    var body: some View {
        Group {
            if chordsManager.state == .idle || chordsManager.state == .downloading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(.secondary)
                    Text("Şarkılar yükleniyor…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(displaySongs) { song in
                    NavigationLink(destination: SongDetailView(song: song, playlist: displaySongs)) {
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
            }
        }
        .navigationTitle("Tüm Şarkılar")
        .searchable(text: $searchText, prompt: "Ara")
        .onChange(of: searchText) { _, newValue in
            // viewModel arama da çalışmaya devam etsin (MySongs vs)
            viewModel.searchText = newValue
        }
    }
}

