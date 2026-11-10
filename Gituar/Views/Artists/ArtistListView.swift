import SwiftUI

/// Bir yükleyiciden gelen sanatçı listesi (Popüler Sanatçılar, Yeni Eklenen Sanatçılar).
struct ArtistListView: View {
    let title: String
    let load: () async throws -> [GituarAPI.Artist]

    private enum Phase: Equatable { case loading, loaded, failed(String) }
    @State private var phase: Phase = .loading
    @State private var artists: [GituarAPI.Artist] = []

    var body: some View {
        Group {
            switch phase {
            case .loading:
                CatalogLoadingView(text: "Sanatçılar yükleniyor…")
            case .failed(let message):
                CatalogLoadFailedView(message: message) { Task { await reload() } }
            case .loaded:
                List(artists) { artist in
                    NavigationLink(destination: ArtistDetailView(slug: artist.slug, name: artist.name)) {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.secondarySystemBackground))
                                    .frame(width: 48, height: 48)
                                Text(artist.name.prefix(1).uppercased())
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(artist.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .lineLimit(1)
                                if let count = artist.songs {
                                    Text("\(count) Şarkı")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
                .scrollEdgeEffectStyle(.soft)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { if artists.isEmpty { await reload() } }
    }

    private func reload() async {
        phase = .loading
        do {
            artists = try await load()
            phase = .loaded
        } catch is CancellationError {
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
