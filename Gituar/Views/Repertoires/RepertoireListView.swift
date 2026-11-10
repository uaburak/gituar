import SwiftUI
import FirebaseFirestore
import Combine

struct RepertoireListView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var showingNew = false
    @State private var newName = ""
    @State private var showingRename = false
    @State private var repertoireToRename: Repertoire?
    @State private var renamedName = ""
    @State private var repertoireToDelete: Repertoire?
    @State private var showingBulkImport = false

    var body: some View {
        Group {
            if viewModel.repertoires.isEmpty {
                VStack(spacing: 8) {
                    Text("Repertuar yok")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("+ butonuna bas")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
                    
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(viewModel.repertoires) { repertoire in
                            NavigationLink(destination: RepertoireDetailView(repertoire: repertoire)) {
                                RepertoireCard(repertoire: repertoire)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .contextMenu {
                                Button {
                                    repertoireToRename = repertoire
                                    renamedName = repertoire.name
                                    showingRename = true
                                } label: {
                                    Label("Düzenle", systemImage: "pencil")
                                }
                                
                                Button(role: .destructive) {
                                    repertoireToDelete = repertoire
                                } label: {
                                    Label("Sil", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(20)
                }
                .scrollEdgeEffectStyle(.soft)
            }
        }
        .navigationTitle("Repertuar")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // Admin: Toplu Repertuar Yükle
                if authViewModel.isAdmin {
                    Button {
                        showingBulkImport = true
                    } label: {
                        Image(systemName: "rectangle.stack.badge.plus")
                    }
                    .accessibilityLabel("Toplu repertuar yükle")
                }

                // Normal: Yeni Repertuar
                Button {
                    showingNew = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Yeni repertuar")
            }
        }
        .alert(
            "Bu repertuar silinsin mi?",
            isPresented: Binding(
                get: { repertoireToDelete != nil },
                set: { if !$0 { repertoireToDelete = nil } }
            ),
            presenting: repertoireToDelete
        ) { repertoire in
            Button("Repertuarı Sil", role: .destructive) {
                viewModel.deleteRepertoire(repertoire)
            }
            Button("Vazgeç", role: .cancel) { }
        } message: { repertoire in
            Text("“\(repertoire.name)” ve içindeki şarkı listesi silinecek. Şarkıların kendisi silinmez.")
        }
        .sheet(isPresented: $showingBulkImport) {
            BulkRepertoireImportView()
                .environmentObject(viewModel)
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
    }
}

struct RepertoireDetailView: View {
    let repertoire: Repertoire
    @EnvironmentObject var viewModel: ChordViewModel
    @State private var showingSavedAlert = false
    @State private var ownerUsername: String?
    @State private var songs: [Song] = []
    @State private var isLoadingSongs = true
    @State private var loadError: String?
    
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    private let searchPublisher = PassthroughSubject<String, Never>()

    var isOwner: Bool {
        repertoire.ownerId == (viewModel.currentUserId ?? "local")
    }

    /// Güncel hâli (kendi repertuarında herkese açma/gizleme anında yansısın)
    private var liveRepertoire: Repertoire {
        (viewModel.repertoires + viewModel.publicRepertoires).first(where: { $0.id != nil && $0.id == repertoire.id }) ?? repertoire
    }

    /// Yalnızca herkese açık repertuar paylaşılabilir.
    private var shareURL: URL? {
        let r = liveRepertoire
        guard r.isPublic == true, let id = r.id else { return nil }
        if let user = r.ownerUsername, !user.isEmpty, let slug = r.slug, !slug.isEmpty,
           let u = user.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
           let sl = slug.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-"))) {
            return URL(string: "https://gituar.com/repertuar/\(u)/\(sl)/")
        }
        return URL(string: "https://gituar.com/repertuar/?id=\(id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id)")
    }

    private var ownerLabel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Repertuar Sahibi")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            Text(isOwner ? "Ben" : (repertoire.ownerId == "local" ? "Ben" : (ownerUsername != nil ? "@\(ownerUsername!)" : "Yükleniyor...")))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(isOwner || repertoire.ownerId == "local" ? .primary : .blue)
                .lineLimit(1)
        }
    }

    /// Repertuarın güncel şarkı kimlikleri (kendi repertuarında Firestore dinleyicisinden gelir).
    private var currentSongIds: [String] {
        viewModel.repertoires.first(where: { $0.id != nil && $0.id == repertoire.id })?.songIds ?? repertoire.songIds
    }

    /// Kimlikleri API'den şarkılara çevirir; silinmiş/eski kimlikler atlanır.
    private func loadSongs() async {
        if songs.isEmpty { isLoadingSongs = true }
        defer { isLoadingSongs = false }
        do {
            songs = try await viewModel.songs(ids: currentSongIds)
            loadError = nil
        } catch is CancellationError {
        } catch {
            if songs.isEmpty { loadError = error.localizedDescription }
        }
    }

    var body: some View {
        let filteredSongs = SongSearch.filter(songs, query: debouncedSearchText)

        Group {
            if songs.isEmpty && isLoadingSongs {
                CatalogLoadingView()
            } else if songs.isEmpty, let loadError {
                CatalogLoadFailedView(message: loadError) {
                    Task { await loadSongs() }
                }
            } else if songs.isEmpty {
                Text("Bu repertuarda henüz şarkı yok.")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredSongs, id: \.docId) { song in
                    NavigationLink(destination: SongDetailView(song: song, playlist: filteredSongs)) {
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
                                songs.removeAll { $0.docId == song.docId }
                            } label: {
                                Label("Sil", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollEdgeEffectStyle(.soft)
                .overlay {
                    if filteredSongs.isEmpty {
                        NoSearchResultsView(query: debouncedSearchText)
                    }
                }
                .searchable(text: $searchText, prompt: "Ara...")
                .onReceive(searchPublisher.debounce(for: .milliseconds(500), scheduler: RunLoop.main)) { newValue in
                    debouncedSearchText = newValue
                }
                .onChange(of: searchText) { _, newValue in
                    searchPublisher.send(newValue)
                }
            }
        }
        .safeAreaInset(edge: .top) {
            VStack {
                HStack {
                    if isOwner || repertoire.ownerId == "local" {
                        ownerLabel
                    } else {
                        // Sahibinin herkese açık profili
                        NavigationLink(destination: PublicProfileView(ownerId: repertoire.ownerId, username: ownerUsername)) {
                            ownerLabel
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Yayınlama Tarihi")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(repertoire.createdAt, style: .date)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.primary)
                    }
                }
            }
            .padding(16)
            .glassEffect(in: .rect(cornerRadius: 20.0))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .navigationTitle(repertoire.name)
        .toolbar {
            // Herkese açık repertuarın web adresi (gituar.com/repertuar/{kullanıcı}/{slug}/)
            if let url = shareURL {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Repertuarı paylaş")
                }
                ToolbarSpacer(.fixed, placement: .navigationBarTrailing)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if isOwner {
                    Menu {
                        Button {
                            viewModel.setRepertoirePublic(repertoire, isPublic: true)
                        } label: {
                            HStack {
                                Text("Herkesle Paylaş")
                                if liveRepertoire.isPublic == true {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        
                        Button {
                            viewModel.setRepertoirePublic(repertoire, isPublic: false)
                        } label: {
                            HStack {
                                Text("Gizli")
                                if liveRepertoire.isPublic != true {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    } label: {
                        Image(systemName: liveRepertoire.isPublic == true ? "globe" : "lock")
                    }
                    .accessibilityLabel("Paylaşım ayarı")
                } else {
                    Button {
                        viewModel.duplicateRepertoire(repertoire)
                        showingSavedAlert = true
                    } label: {
                        Image(systemName: viewModel.isRepertoireCopied(repertoire) ? "checkmark.circle.fill" : "plus.square.on.square")
                    }
                    .accessibilityLabel("Repertuarlarıma kaydet")
                    .disabled(viewModel.isRepertoireCopied(repertoire))
                }
            }
        }
        .alert("Kaydedildi", isPresented: $showingSavedAlert) {
            Button("Tamam", role: .cancel) { }
        } message: {
            Text("Repertuar listenize başarıyla eklendi.")
        }
        .task(id: currentSongIds) { await loadSongs() }
        .task {
            guard !isOwner && repertoire.ownerId != "local" else { return }
            if let known = repertoire.ownerUsername, !known.isEmpty { ownerUsername = known; return }
            do {
                let doc = try await Firestore.firestore().collection("users").document(repertoire.ownerId).getDocument()
                if let data = doc.data(), let username = data["username"] as? String {
                    self.ownerUsername = username
                }
            } catch {
                print("Error fetching username: \(error)")
            }
        }
    }
}
