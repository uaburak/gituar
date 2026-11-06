import SwiftUI
import Combine

struct AllArtistsView: View {
    @ObservedObject private var adMobManager = AdMobManager.shared
    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    private let searchPublisher = PassthroughSubject<String, Never>()

    private enum Phase: Equatable { case loading, loaded, failed(String) }
    private static let pageSize = 100

    @State private var artists: [GituarAPI.Artist] = []
    @State private var phase: Phase = .loading
    @State private var canLoadMore = false
    @State private var isLoadingMore = false

    // Arama (API)
    @State private var searchResults: [GituarAPI.Artist] = []
    @State private var searchQuery = ""
    @State private var isSearching = false
    @State private var searchError: String?

    private var trimmedQuery: String {
        debouncedSearchText.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                CatalogLoadingView(text: "Sanatçılar yükleniyor…")
            case .failed(let message):
                CatalogLoadFailedView(message: message) { Task { await reload() } }
            case .loaded:
                if trimmedQuery.isEmpty {
                    artistListBody(artists, paged: true)
                } else if let searchError, searchResults.isEmpty {
                    CatalogLoadFailedView(message: searchError) { Task { await runSearch(trimmedQuery) } }
                } else if searchResults.isEmpty && (isSearching || searchQuery != trimmedQuery) {
                    CatalogLoadingView(text: "Aranıyor…")
                } else {
                    artistListBody(searchResults, paged: false)
                }
            }
        }
        .navigationTitle("Sanatçılar")
        .searchable(text: $searchText, prompt: "Sanatçı ara...")
        .onReceive(searchPublisher.debounce(for: .milliseconds(400), scheduler: RunLoop.main)) { newValue in
            debouncedSearchText = newValue
        }
        .onChange(of: searchText) { _, newValue in
            searchPublisher.send(newValue)
        }
        .task { if artists.isEmpty { await reload() } }
        .task(id: trimmedQuery) { await runSearch(trimmedQuery) }
    }

    // MARK: - Artist List

    @ViewBuilder
    private func artistListBody(_ list: [GituarAPI.Artist], paged: Bool) -> some View {
        if list.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "person.2.slash")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("Sanatçı bulunamadı.")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(Array(list.enumerated()), id: \.element.slug) { index, artist in
                    NavigationLink(destination: ArtistDetailView(slug: artist.slug, name: artist.name)) {
                        ArtistRowCard(artist: artist.name, songCount: artist.songs ?? 0)
                    }
                    .onAppear {
                        if paged && index == list.count - 1 { Task { await loadMore() } }
                    }
                    // Her 10 satırda bir yerel reklam (Plus'ta yok)
                    if AdPlacements.shouldShowNativeAd(afterRow: index, isAdFree: adMobManager.isAdFree) {
                        NativeAdRow()
                    }
                }
                if paged && isLoadingMore {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollEdgeEffectStyle(.soft)
            .refreshable { await reload() }
        }
    }

    // MARK: - Loading

    private func reload() async {
        if artists.isEmpty { phase = .loading }
        do {
            let page = try await GituarAPI.shared.artists(limit: Self.pageSize, offset: 0)
            artists = Self.unique(page)
            canLoadMore = page.count == Self.pageSize
            phase = .loaded
        } catch is CancellationError {
        } catch {
            if artists.isEmpty { phase = .failed(error.localizedDescription) }
        }
    }

    private func loadMore() async {
        guard canLoadMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await GituarAPI.shared.artists(limit: Self.pageSize, offset: artists.count)
            artists = Self.unique(artists + page)
            canLoadMore = page.count == Self.pageSize
        } catch {
            print("⚠️ AllArtistsView.loadMore: \(error.localizedDescription)")
        }
    }

    private func runSearch(_ query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            searchQuery = ""
            searchError = nil
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            let results = try await GituarAPI.shared.search(query, limit: 50)
            guard !Task.isCancelled else { return }
            searchResults = results.artists
            searchQuery = query
            searchError = nil
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            searchResults = []
            searchQuery = query
            searchError = error.localizedDescription
        }
    }

    private static func unique(_ artists: [GituarAPI.Artist]) -> [GituarAPI.Artist] {
        var seen = Set<String>()
        return artists.filter { seen.insert($0.slug).inserted }
    }
}
