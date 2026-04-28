import SwiftUI

struct RepertoireListView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @State private var showingNew = false
    @State private var newName = ""

    var body: some View {
        List {
            ForEach(viewModel.repertoires) { repertoire in
                NavigationLink(destination: RepertoireDetailView(repertoire: repertoire)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(repertoire.name)
                            .font(.system(size: 15, weight: .medium))
                        Text("\(repertoire.songIds.count) şarkı")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .onDelete(perform: viewModel.deleteRepertoire)
        }
        .listStyle(.plain)
        .navigationTitle("Repertuar")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingNew = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                EditButton()
            }
        }
        .alert("Yeni Repertuar", isPresented: $showingNew) {
            TextField("İsim", text: $newName)
            Button("İptal", role: .cancel) { newName = "" }
            Button("Oluştur") {
                if !newName.trimmingCharacters(in: .whitespaces).isEmpty {
                    viewModel.addRepertoire(name: newName)
                    newName = ""
                }
            }
        }
        .overlay {
            if viewModel.repertoires.isEmpty {
                VStack(spacing: 8) {
                    Text("Repertuar yok")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("+ butonuna bas")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct RepertoireDetailView: View {
    let repertoire: Repertoire
    @EnvironmentObject var viewModel: ChordViewModel

    var body: some View {
        let songs = viewModel.songs(for: repertoire)
        Group {
            if songs.isEmpty {
                Text("Bu repertuarda henüz şarkı yok.")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(songs, id: \.docId) { song in
                    NavigationLink(destination: SongDetailView(song: song)) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(song.songName)
                                .font(.system(size: 15, weight: .medium))
                            Text(song.artist)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(repertoire.name)
    }
}
