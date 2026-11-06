import SwiftUI

struct PendingApprovalListView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @State private var searchText: String = ""
    @State private var isLoading = true
    
    var filtered: [Song] {
        SongSearch.filter(viewModel.pendingSongs, query: searchText)
    }

    var body: some View {
        Group {
            if isLoading && viewModel.pendingSongs.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.pendingSongs.isEmpty, let error = viewModel.pendingError {
                CatalogLoadFailedView(message: error) {
                    Task { await viewModel.fetchPendingSongs() }
                }
            } else if viewModel.pendingSongs.isEmpty {
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
                    NavigationLink(destination: SongDetailView(song: song, playlist: filtered, isApprovalMode: true)) {
                        SongRowCard(song: song)
                    }
                }
                .listStyle(.plain)
                .scrollEdgeEffectStyle(.soft)
                .searchable(text: $searchText, prompt: "Bekleyenlerde ara...")
                .refreshable { await viewModel.fetchPendingSongs() }
            }
        }
        .navigationTitle("Onay Bekleyenler")
        .task {
            await viewModel.fetchPendingSongs()
            isLoading = false
        }
    }
}
