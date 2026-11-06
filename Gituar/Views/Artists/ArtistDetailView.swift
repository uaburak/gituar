import SwiftUI

struct ArtistDetailView: View {
    let slug: String
    let name: String
    @EnvironmentObject var viewModel: ChordViewModel

    private enum Phase: Equatable { case loading, loaded, failed(String) }
    @State private var phase: Phase = .loading
    @State private var songs: [Song] = []

    init(slug: String, name: String) {
        self.slug = slug
        self.name = name
    }

    /// Şarkı kaydından (slug yoksa addan üretilir).
    init(song: Song) {
        self.init(slug: song.resolvedArtistSlug, name: song.artist)
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                CatalogLoadingView()
            case .failed(let message):
                CatalogLoadFailedView(message: message) { Task { await load(force: true) } }
            case .loaded:
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
                    .refreshable { await load(force: true) }
                }
            }
        }
        .navigationTitle(name)
        .task { if songs.isEmpty { await load(force: false) } }
    }

    private func load(force: Bool) async {
        do {
            let detail = try await viewModel.artistDetail(slug: slug, forceReload: force)
            var seen = Set<String>()
            songs = detail.songs.filter { seen.insert($0.docId).inserted }
            phase = .loaded
        } catch let error as GituarAPIError where error.isNotFound {
            songs = []
            phase = .loaded
        } catch is CancellationError {
        } catch {
            if songs.isEmpty { phase = .failed(error.localizedDescription) }
        }
    }
}
