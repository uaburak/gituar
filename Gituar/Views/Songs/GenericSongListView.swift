import SwiftUI
import Combine

/// Şarkı listesi: elde hazır bir dizi, API sıralaması (sayfalı) ya da bir yükleyiciden gelir.
struct GenericSongListView: View {
    enum Source {
        case songs([Song])
        case sorted(GituarAPI.SongSort)
        case loader(() async throws -> [Song])
    }

    let title: String
    let source: Source

    init(title: String, songs: [Song]) {
        self.title = title
        self.source = .songs(songs)
    }

    init(title: String, sort: GituarAPI.SongSort) {
        self.title = title
        self.source = .sorted(sort)
    }

    init(title: String, load: @escaping () async throws -> [Song]) {
        self.title = title
        self.source = .loader(load)
    }

    private enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private static let pageSize = 50

    @ObservedObject private var adMobManager = AdMobManager.shared
    @State private var songs: [Song] = []
    @State private var phase: Phase = .loading
    @State private var canLoadMore = false
    @State private var isLoadingMore = false
    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    private let searchPublisher = PassthroughSubject<String, Never>()

    private var filtered: [Song] {
        SongSearch.filter(songs, query: debouncedSearchText)
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                CatalogLoadingView()
            case .failed(let message):
                CatalogLoadFailedView(message: message) {
                    Task { await reload() }
                }
            case .loaded:
                if songs.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("Bu listede henüz şarkı yok.")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    listBody
                }
            }
        }
        .navigationTitle(title)
        .task { await initialLoad() }
    }

    private var listBody: some View {
        let rows = filtered
        return List {
            ForEach(Array(rows.enumerated()), id: \.element.docId) { index, song in
                NavigationLink(destination: SongDetailView(song: song, playlist: rows)) {
                    SongRowCard(song: song)
                }
                .onAppear {
                    if index == rows.count - 1 { Task { await loadMore() } }
                }
                // Her 10 satırda bir yerel reklam (Pro'da yok)
                if AdPlacements.shouldShowNativeAd(afterRow: index, isAdFree: adMobManager.isAdFree) {
                    NativeAdRow()
                }
            }
            if isLoadingMore {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollEdgeEffectStyle(.soft)
        .refreshable { await reload() }
        .overlay {
            if rows.isEmpty {
                NoSearchResultsView(query: debouncedSearchText)
            }
        }
        .searchable(text: $searchText, prompt: "Ara...")
        .onReceive(searchPublisher.debounce(for: .milliseconds(400), scheduler: RunLoop.main)) { newValue in
            debouncedSearchText = newValue
        }
        .onChange(of: searchText) { _, newValue in
            searchPublisher.send(newValue)
        }
    }

    // MARK: - Loading

    private func initialLoad() async {
        // Geri dönüşte (detaydan) listeyi yeniden çekme
        guard phase == .loading || songs.isEmpty else { return }
        await reload()
    }

    private func reload() async {
        if songs.isEmpty { phase = .loading }
        do {
            switch source {
            case .songs(let list):
                songs = list
                canLoadMore = false
            case .sorted(let sort):
                let page = try await GituarAPI.shared.songs(sort: sort, limit: Self.pageSize, offset: 0)
                songs = Self.unique(page)
                canLoadMore = page.count == Self.pageSize
            case .loader(let load):
                songs = Self.unique(try await load())
                canLoadMore = false
            }
            phase = .loaded
        } catch is CancellationError {
        } catch {
            if songs.isEmpty {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func loadMore() async {
        guard case .sorted(let sort) = source, canLoadMore, !isLoadingMore, debouncedSearchText.isEmpty else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await GituarAPI.shared.songs(sort: sort, limit: Self.pageSize, offset: songs.count)
            songs = Self.unique(songs + page)
            canLoadMore = page.count == Self.pageSize
        } catch {
            // Sonraki kaydırmada yeniden denenir
            print("⚠️ GenericSongListView.loadMore: \(error.localizedDescription)")
        }
    }

    /// List kimlikleri tekrarsız olmalı (sayfalar arasında kayan sıralamada aynı şarkı iki kez gelebilir).
    private static func unique(_ songs: [Song]) -> [Song] {
        var seen = Set<String>()
        return songs.filter { seen.insert($0.docId).inserted }
    }
}
