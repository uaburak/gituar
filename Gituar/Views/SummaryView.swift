import SwiftUI

struct SummaryView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var showSignOut = false

    var topArtists: [(artist: String, count: Int)] {
        Dictionary(grouping: viewModel.recentlyPlayed, by: { $0.artist })
            .map { (artist: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        List {
            // Profil
            Section {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color(.secondarySystemBackground))
                            .frame(width: 52, height: 52)
                        Text(authViewModel.userInitials)
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(authViewModel.displayName)
                            .font(.system(size: 16, weight: .semibold))
                        if !authViewModel.userEmail.isEmpty {
                            Text(authViewModel.userEmail)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            // İstatistikler
            Section("İstatistikler") {
                StatRow(label: "Çalınan şarkı", value: "\(viewModel.recentlyPlayed.count)")
                StatRow(label: "Repertuar sayısı", value: "\(viewModel.repertoires.count)")
                StatRow(label: "Farklı sanatçı", value: "\(Set(viewModel.recentlyPlayed.map { $0.artist }).count)")
            }

            // Son Çalınanlar
            if !viewModel.recentlyPlayed.isEmpty {
                Section("Son Çalınanlar") {
                    ForEach(Array(viewModel.recentlyPlayed.prefix(5).enumerated()), id: \.element.id) { index, song in
                        NavigationLink(destination: SongDetailView(song: song)) {
                            HStack(spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(song.songName)
                                        .font(.system(size: 14, weight: .medium))
                                    Text(song.artist)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }

            // En Çok Çalınan Sanatçılar
            if !topArtists.isEmpty {
                Section("En Çok Çalınan Sanatçılar") {
                    ForEach(Array(topArtists.enumerated()), id: \.element.artist) { index, item in
                        NavigationLink(destination: ArtistDetailView(artist: item.artist)) {
                            HStack {
                                Text("\(index + 1)")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .frame(width: 20)
                                Text(item.artist)
                                    .font(.system(size: 14, weight: .medium))
                                Spacer()
                                Text("\(item.count) şarkı")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }

            // Çıkış
            Section {
                Button(role: .destructive) {
                    showSignOut = true
                } label: {
                    Text("Çıkış Yap")
                        .font(.system(size: 15))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Profil")
        .alert("Çıkış Yap", isPresented: $showSignOut) {
            Button("İptal", role: .cancel) {}
            Button("Çıkış Yap", role: .destructive) { authViewModel.signOut() }
        } message: {
            Text("Hesabından çıkmak istiyor musun?")
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 15))
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
        }
    }
}
