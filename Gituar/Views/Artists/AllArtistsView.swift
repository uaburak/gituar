import SwiftUI
import Combine

struct AllArtistsView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @EnvironmentObject var chordsManager: ChordsStorageManager
    @ObservedObject private var adMobManager = AdMobManager.shared
    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    private let searchPublisher = PassthroughSubject<String, Never>()

    // Kaynak her zaman viewModel — Storage + user_chords merge edilmiş halde burada
    private var artistList: [String] {
        if debouncedSearchText.isEmpty { return viewModel.artists }
        let query = debouncedSearchText.turkeyNormalized
        return viewModel.artists.filter { $0.turkeyNormalized.contains(query) }
    }

    private func songCount(for artist: String) -> Int {
        viewModel.artistSongCount[artist] ?? 0
    }

    var body: some View {
        Group {
            switch chordsManager.state {
            case .idle, .downloading:
                // Dosya henüz inmedi — küçük spinner göster
                CatalogLoadingView(text: "Sanatçılar yükleniyor…")

            case .failed:
                // İndirme başarısız — elde veri varsa (user-chords) onunla devam et
                if viewModel.artists.isEmpty {
                    CatalogLoadFailedView()
                } else {
                    artistListBody
                }

            case .ready:
                artistListBody
            }
        }
        .navigationTitle("Sanatçılar")
        .searchable(text: $searchText, prompt: "Sanatçı ara...")
        .onReceive(searchPublisher.debounce(for: .milliseconds(500), scheduler: RunLoop.main)) { newValue in
            debouncedSearchText = newValue
        }
        .onChange(of: searchText) { _, newValue in
            searchPublisher.send(newValue)
        }
    }

    // MARK: - Artist List

    @ViewBuilder
    private var artistListBody: some View {
        if artistList.isEmpty {
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
                ForEach(Array(artistList.enumerated()), id: \.element) { index, artist in
                NavigationLink(destination: ArtistDetailView(artist: artist)) {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemBackground))
                                .frame(width: 48, height: 48)
                            Text(artist.prefix(1).uppercased())
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(artist)
                                .font(.system(size: 15, weight: .semibold))
                                .lineLimit(1)
                            Text("\(songCount(for: artist)) Şarkı")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        // List, NavigationLink satırına kendi okunu ekler — ayrıca chevron çizme (çift ok oluyordu)
                        Spacer()
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
        }
    }
}

