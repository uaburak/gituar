import SwiftUI
import FirebaseAuth
import UniformTypeIdentifiers

// MARK: - Shared Import Model

struct ImportableSong: Codable, Identifiable {
    var id: String { (songName ?? "") + (artist ?? "") }
    /// İsteğe bağlı. Dosyadaki tüm şarkılarda varsa içe aktarımda bu ID'ler korunur.
    var docId: String?
    var songName: String?
    var artist: String?
    var originalKey: String?
    var content: String?
}

// MARK: - MySongsView

struct MySongsView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @EnvironmentObject var authViewModel: AuthViewModel

    @State private var songToEdit: Song?
    @State private var songToDelete: Song?
    @State private var navigateToNewSong = false

    var body: some View {
        Group {
            if let userId = authViewModel.currentUser?.uid {
                let userSongs = viewModel.userSongs(userId: userId)

                if userSongs.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "music.quarternote.3")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("Henüz kendi şarkını oluşturmadın.")
                            .font(.headline)
                        Text("Kendi şarkılarını ve akorlarını ekleyerek burada listeleyebilirsin.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    List(userSongs, id: \.docId) { song in
                        NavigationLink(destination: SongDetailView(song: song, playlist: userSongs)) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(song.songName)
                                        .font(.system(size: 16, weight: .semibold))
                                    Spacer()
                                    if song.status == "pending" {
                                        StatusBadge(text: "Onay Bekliyor", color: .orange, icon: nil)
                                    } else if song.status == "approved" {
                                        StatusBadge(text: "Yayında", color: .green, icon: nil)
                                    } else if song.status == "rejected" {
                                        StatusBadge(text: "Reddedildi", color: .red, icon: nil)
                                    } else {
                                        StatusBadge(text: "Taslak", color: .gray, icon: nil)
                                    }
                                }
                                Text(song.artist)
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            // Silme geri alınamaz — önce onay sor
                            Button {
                                songToDelete = song
                            } label: {
                                Label("Sil", systemImage: "trash")
                            }
                            .tint(.red)
                            Button {
                                songToEdit = song
                            } label: {
                                Label("Düzenle", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                    }
                    .listStyle(.plain)
                    .scrollEdgeEffectStyle(.soft)
                    .refreshable { await viewModel.refresh() }
                }
            } else {
                ContentUnavailableView {
                    Label("Giriş yapmalısın", systemImage: "person.crop.circle.badge.plus")
                } description: {
                    Text("Kendi şarkılarını eklemek ve görmek için bir hesapla giriş yap.")
                } actions: {
                    // Misafir modundan çıkıp giriş ekranına döner
                    Button("Giriş Yap") { authViewModel.signOut() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Şarkılarım")
        .alert(
            "Bu şarkı kalıcı olarak silinsin mi?",
            isPresented: Binding(
                get: { songToDelete != nil },
                set: { if !$0 { songToDelete = nil } }
            ),
            presenting: songToDelete
        ) { song in
            Button("Şarkıyı Sil", role: .destructive) {
                viewModel.deleteSong(song)
            }
            Button("Vazgeç", role: .cancel) { }
        } message: { song in
            Text("“\(song.songName)” silinecek. Bu işlem geri alınamaz.")
        }
        .navigationDestination(isPresented: $navigateToNewSong) {
            EditSongView(song: nil)
        }
        .navigationDestination(item: $songToEdit) { song in
            EditSongView(song: song)
        }
        .toolbar {
            // Misafir şarkı kaydedemez — eklemeyi yalnızca giriş yapmış kullanıcıya göster
            if authViewModel.currentUser != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { navigateToNewSong = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Yeni şarkı")
                }
            }
        }
    }
}

// MARK: - StatusBadge

struct StatusBadge: View {
    let text: String
    let color: Color
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(text)
                .font(.system(size: 10, weight: .bold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .foregroundColor(color)
        .cornerRadius(6)
    }
}

// MARK: - JSON Document Picker

struct JSONImportPickerView: UIViewControllerRepresentable {
    var onFilePicked: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.json], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: JSONImportPickerView
        init(_ parent: JSONImportPickerView) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.onFilePicked(url)
            parent.dismiss()
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.dismiss()
        }
    }
}

// MARK: - EditSongView

struct EditSongView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss

    let song: Song?

    @State private var songName: String = ""
    @State private var artist: String = ""
    @State private var originalKey: String = "C"
    @State private var content: String = ""
    @State private var status: String = "draft"

    // JSON Import
    @State private var showImportPicker = false
    @State private var pendingImportData: Data? = nil
    @State private var parsedImportSongs: [ImportableSong] = []
    @State private var showImportPreview = false
    @State private var importParseError: String? = nil

    // App Store Guideline 1.2: içerik göndermeden önce kullanım şartlarının kabulü ve uygunsuz ifade filtresi
    @AppStorage("ugcTermsAccepted") private var ugcTermsAccepted = false
    @State private var showTermsSheet = false
    @State private var showFilterAlert = false

    private var canSave: Bool {
        !songName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !artist.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Yayına (onaya) göndermek için akor/söz içeriği de dolu olmalı.
    private var canPublish: Bool {
        canSave && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "guitars.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 16)
                    Text(song == nil ? "Yeni Şarkı Oluştur" : "Şarkıyı Düzenle")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(song == nil ? "Şarkının sözlerini ve akorlarını aşağıya ekle." : "Şarkında yapmak istediğin değişiklikleri yap.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 16) {
                    formField(text: $songName, placeholder: "Şarkı Adı")

                    HStack(spacing: 16) {
                        formField(text: $artist, placeholder: "Sanatçı")

                        Menu {
                            ForEach(ChordTransposer.selectableKeys, id: \.self) { note in
                                Button { originalKey = note } label: { Text(note) }
                            }
                        } label: {
                            HStack {
                                Text(originalKey).foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .foregroundColor(.secondary).font(.caption)
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color(.separator), lineWidth: 1))
                        }
                        .frame(width: 90)
                    }

                    // Text Editor
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $content)
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                            .padding(8)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        if content.isEmpty {
                            Text("Akorları ve sözleri buraya yazın...\n\nÖrnek:\nAm         G\nBu bir şarkı sözü...")
                                .font(.system(size: 15, weight: .medium, design: .monospaced))
                                .foregroundColor(Color(.placeholderText))
                                .padding(.horizontal, 12)
                                .padding(.top, 16)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(minHeight: 250)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator), lineWidth: 1))
                }
                .padding(.horizontal, 24)

                // Status Badges
                if status == "pending" {
                    StatusBadge(text: "Şarkınız onay bekliyor", color: .orange, icon: "clock.fill")
                } else if status == "approved" {
                    StatusBadge(text: "Şarkınız yayında", color: .green, icon: "checkmark.seal.fill")
                } else if status == "rejected" {
                    StatusBadge(text: "Reddedildi. Lütfen düzenleyip tekrar gönderin.", color: .red, icon: "xmark.octagon.fill")
                }

                // Actions
                HStack(spacing: 12) {
                    Button {
                        saveSong(asStatus: status == "approved" ? "approved" : "draft")
                    } label: {
                        // Yayındaki şarkıda bu buton taslağa çekmez, değişikliği kaydeder
                        Text(status == "approved" ? "Kaydet" : "Taslak Kaydet")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color(.separator), lineWidth: 1))
                    }
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.5)

                    if status != "pending" && status != "approved" {
                        Button {
                            attemptPublish()
                        } label: {
                            Text("Yayınla")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color.accentColor)
                                .clipShape(Capsule())
                        }
                        .disabled(!canPublish)
                        .opacity(canPublish ? 1 : 0.5)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .scrollEdgeEffectStyle(.soft)
        .navigationTitle(song == nil ? "Yeni Şarkı" : "Düzenle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                // JSON İçe Aktar — sadece admin + yeni şarkı ekranında
                if song == nil && authViewModel.isAdmin {
                    Button {
                        showImportPicker = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("JSON'dan içe aktar")
                }
                // Paylaş — sadece mevcut şarkıda
                if let song = song, let url = URL(string: "gituar://song/\(song.docId)") {
                    ShareLink(item: url, message: Text("\(song.artist) - \(song.songName) şarkısına Gituar'dan göz at!")) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .onAppear {
            if let song = song {
                songName = song.songName
                artist = song.artist
                originalKey = song.originalKey
                content = song.content
                status = song.status ?? "draft"
            }
        }
        .sheet(isPresented: $showImportPicker) {
            JSONImportPickerView { url in
                parseJSON(from: url)
            }
        }
        .sheet(isPresented: $showTermsSheet) {
            UGCTermsSheet {
                ugcTermsAccepted = true
                showTermsSheet = false
                attemptPublish()
            }
            .presentationDetents([.large])
        }
        .alert("İçerik Gönderilemedi", isPresented: $showFilterAlert) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text("Şarkı adı, sanatçı ya da sözlerde uygunsuz bir ifade var. Küfür, hakaret ve nefret söylemi içeren içerikler yayımlanmaz.")
        }
        .sheet(isPresented: $showImportPreview) {
            JSONImportPreviewView(
                songs: parsedImportSongs,
                rawData: pendingImportData ?? Data()
            )
        }
        .alert("Geçersiz Dosya", isPresented: .constant(importParseError != nil)) {
            Button("Tamam") { importParseError = nil }
        } message: {
            Text(importParseError ?? "")
        }
    }

    // MARK: - Parse JSON

    private func parseJSON(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            importParseError = "Dosya okunamadı."
            return
        }
        guard let songs = try? JSONDecoder().decode([ImportableSong].self, from: data), !songs.isEmpty else {
            importParseError = "Geçersiz JSON formatı.\nDosyanın [{\"songName\", \"artist\", \"originalKey\", \"content\"}] formatında olduğundan emin ol."
            return
        }
        pendingImportData = data
        parsedImportSongs = songs
        showImportPreview = true
    }

    // MARK: - Helpers

    private func formField(text: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: text)
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color(.separator), lineWidth: 1))
    }

    /// Yayına göndermeden önce: şartlar kabul edilmiş olmalı, içerik filtreden geçmeli.
    private func attemptPublish() {
        guard ugcTermsAccepted else { showTermsSheet = true; return }
        if ContentFilter.firstObjectionableWord(in: songName, artist, content) != nil {
            showFilterAlert = true
            return
        }
        saveSong(asStatus: "pending")
    }

    private func saveSong(asStatus targetStatus: String) {
        guard let userId = authViewModel.currentUser?.uid else { return }
        let username = authViewModel.userProfile?.username ?? authViewModel.displayName
        var finalStatus = targetStatus
        if targetStatus == "pending" && authViewModel.isAdmin { finalStatus = "approved" }

        let songToSave = Song(
            docId: song?.docId ?? "",
            artist: artist.trimmingCharacters(in: .whitespaces),
            songName: songName.trimmingCharacters(in: .whitespaces),
            originalKey: originalKey,
            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: song?.createdAt ?? Date(),
            totalViews: song?.totalViews ?? 0,
            recentViews: song?.recentViews ?? 0,
            repertoireAdds: song?.repertoireAdds ?? 0,
            ownerId: userId,
            addedBy: song?.addedBy ?? username,
            status: finalStatus
        )
        viewModel.saveSong(songToSave)
        dismiss()
    }
}


/// İlk gönderimden önce gösterilen kullanım şartları özeti. Kabul edilmeden içerik yayına gönderilemez.
struct UGCTermsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAccept: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Paylaşmadan önce")
                        .font(.title2.weight(.bold))
                    Text("Gituar'da akorları kullanıcılar ekler. Paylaştığın içerikten sen sorumlusun. Göndermeden önce şu kuralları kabul etmelisin:")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 12) {
                        termRow("hand.raised.fill", "Uygunsuz içeriğe ve kötüye kullanan kullanıcılara sıfır tolerans: küfür, hakaret, nefret söylemi, taciz ve müstehcen içerik yasaktır.")
                        termRow("music.note", "Yalnızca müzik eğitimi amacıyla akor ve söz paylaş. Eserlerin hakları sahiplerine aittir.")
                        termRow("checkmark.shield.fill", "Gönderilen her şarkı editör onayından sonra yayımlanır. Kurallara uymayan içerik kaldırılır.")
                        termRow("flag.fill", "Şikayet edilen içerikler 24 saat içinde incelenir. Kuralları ihlal eden hesaplar kapatılır.")
                    }
                    NavigationLink("Kullanım Şartlarının tamamı") { TermsOfUseView() }
                        .font(.footnote)
                }
                .padding(24)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button {
                        onAccept()
                    } label: {
                        Text("Kabul Ediyorum")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    }
                    Button("Vazgeç") { dismiss() }
                        .font(.system(size: 15, weight: .medium))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                .background(.bar)
            }
        }
    }

    private func termRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
        }
    }
}
