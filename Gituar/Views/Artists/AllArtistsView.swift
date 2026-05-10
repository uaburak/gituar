import SwiftUI
import Combine

struct AllArtistsView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    private let searchPublisher = PassthroughSubject<String, Never>()
    
    var filteredArtists: [String] {
        if debouncedSearchText.isEmpty { return viewModel.artists }
        let query = debouncedSearchText.turkeyNormalized
        return viewModel.artists.filter { $0.turkeyNormalized.contains(query) }
    }
    
    var body: some View {
        List(filteredArtists, id: \.self) { artist in
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
                        Text("\(viewModel.songsForArtist(artist).count) Şarkı")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(.systemGray4))
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.plain)
        .navigationTitle("Sanatçılar")
        .searchable(text: $searchText, prompt: "Sanatçı ara...")
        .onReceive(searchPublisher.debounce(for: .milliseconds(500), scheduler: RunLoop.main)) { newValue in
            debouncedSearchText = newValue
        }
        .onChange(of: searchText) { _, newValue in
            searchPublisher.send(newValue)
        }
    }
}
