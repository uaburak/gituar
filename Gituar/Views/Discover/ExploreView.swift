import SwiftUI

struct ExploreView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @EnvironmentObject var chordsManager: ChordsStorageManager
    @ObservedObject private var adMobManager = AdMobManager.shared
    @State private var searchText: String = ""
    @State private var displaySongs: [Song] = []

    /// Sorgu ya da şarkı listesi değiştiğinde aramayı yeniden başlatır (öncekini iptal ederek).
    private struct SearchTrigger: Equatable {
        let query: String
        let songsVersion: Int
    }

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    private var isCatalogFailed: Bool {
        if case .failed = chordsManager.state { return true }
        return false
    }

    var body: some View {
        Group {
            if chordsManager.state == .idle || chordsManager.state == .downloading {
                CatalogLoadingView()
            } else if isCatalogFailed && viewModel.visibleSongs.isEmpty {
                CatalogLoadFailedView()
            } else {
                List {
                    ForEach(Array(displaySongs.enumerated()), id: \.element.docId) { index, song in
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
                    // Her 10 satırda bir yerel reklam (Plus'ta yok)
                    if AdPlacements.shouldShowNativeAd(afterRow: index, isAdFree: adMobManager.isAdFree) {
                        NativeAdRow()
                    }
                    }
                }
                .listStyle(.plain)
                .scrollEdgeEffectStyle(.soft)
                .overlay {
                    if displaySongs.isEmpty && !trimmedQuery.isEmpty {
                        NoSearchResultsView(query: trimmedQuery)
                    }
                }
                .refreshable { await viewModel.refresh() }
            }
        }
        .navigationTitle("Tüm Şarkılar")
        .searchable(text: $searchText, prompt: "Ara")
        .onAppear {
            if displaySongs.isEmpty && trimmedQuery.isEmpty {
                displaySongs = viewModel.visibleSongs
            }
        }
        .task(id: SearchTrigger(query: trimmedQuery, songsVersion: viewModel.visibleSongsVersion)) {
            await updateDisplayedSongs()
        }
    }

    private func updateDisplayedSongs() async {
        let songs = viewModel.visibleSongs
        let query = trimmedQuery
        guard !query.isEmpty else {
            displaySongs = songs
            return
        }
        // Debounce — yazmaya devam edilirse .task(id:) bu görevi iptal eder
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }

        let results = await Task.detached(priority: .userInitiated) {
            SongSearch.filter(songs, query: query, ranked: true)
        }.value
        guard !Task.isCancelled else { return }
        displaySongs = results
    }
}
