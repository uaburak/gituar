import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @State private var searchText: String = ""

    var filtered: [Repertoire] {
        if searchText.isEmpty { return viewModel.publicRepertoires }
        return viewModel.publicRepertoires.filter {
            $0.name.turkeyNormalized.contains(searchText.turkeyNormalized)
        }
    }

    var body: some View {
        List(filtered) { repertoire in
            NavigationLink(destination: RepertoireDetailView(repertoire: repertoire)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(repertoire.name)
                        .font(.system(size: 16, weight: .semibold))
                    HStack(spacing: 4) {
                        Text("\(repertoire.songIds.count) şarkı")
                    }
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.plain)
        .navigationTitle("Keşfet")
        .searchable(text: $searchText, prompt: "Repertuar ara")
    }
}
