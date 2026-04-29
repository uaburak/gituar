import SwiftUI

struct RepertoireListView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @State private var showingNew = false
    @State private var newName = ""
    @State private var showingRename = false
    @State private var repertoireToRename: Repertoire?
    @State private var renamedName = ""

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
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        viewModel.deleteRepertoire(repertoire)
                    } label: {
                        Label("Sil", systemImage: "trash")
                    }
                    
                    Button {
                        repertoireToRename = repertoire
                        renamedName = repertoire.name
                        showingRename = true
                    } label: {
                        Label("Düzenle", systemImage: "pencil")
                    }
                    .tint(.orange)
                }
            }
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
        .alert("Repertuarı Düzenle", isPresented: $showingRename) {
            TextField("İsim", text: $renamedName)
            Button("İptal", role: .cancel) { 
                repertoireToRename = nil
                renamedName = ""
            }
            Button("Kaydet") {
                if let repertoire = repertoireToRename, !renamedName.trimmingCharacters(in: .whitespaces).isEmpty {
                    viewModel.renameRepertoire(repertoire, newName: renamedName)
                    repertoireToRename = nil
                    renamedName = ""
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
    @State private var showingSavedAlert = false

    var isOwner: Bool {
        repertoire.ownerId == (viewModel.currentUserId ?? "local")
    }

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
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if isOwner {
                            Button(role: .destructive) {
                                viewModel.removeSong(song, from: repertoire)
                            } label: {
                                Label("Sil", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(repertoire.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isOwner {
                    Menu {
                        Button {
                            viewModel.setRepertoirePublic(repertoire, isPublic: true)
                        } label: {
                            HStack {
                                Text("Herkesle Paylaş")
                                if repertoire.isPublic == true {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        
                        Button {
                            viewModel.setRepertoirePublic(repertoire, isPublic: false)
                        } label: {
                            HStack {
                                Text("Gizli")
                                if repertoire.isPublic == false || repertoire.isPublic == nil {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                } else {
                    Button {
                        viewModel.duplicateRepertoire(repertoire)
                        showingSavedAlert = true
                    } label: {
                        Image(systemName: viewModel.isRepertoireCopied(repertoire) ? "checkmark.circle.fill" : "plus.square.on.square")
                    }
                    .disabled(viewModel.isRepertoireCopied(repertoire))
                }
            }
        }
        .alert("Kaydedildi", isPresented: $showingSavedAlert) {
            Button("Tamam", role: .cancel) { }
        } message: {
            Text("Repertuar listenize başarıyla eklendi.")
        }
    }
}
