import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - JSONImportPreviewView
//
// JSON dosyasından parse edilen şarkıları listeler.
// "Onayla" butonuna basınca şarkıları Firestore `songs` koleksiyonuna yazar (resmi katalog):
//   1) `catalog/meta.seq` üzerinde N'lik bir seq aralığı ayrılır (transaction),
//   2) 450'lik batch'lerle `songs/{id}` dokümanları yazılır (merge).
// Yazma bitince ChordsStorageManager fark senkronu ile yeni şarkıları alır; web yayını `npm run publish` ile üretilir.

struct JSONImportPreviewView: View {
    let songs: [ImportableSong]
    let rawData: Data

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authViewModel: AuthViewModel

    @State private var isUploading = false
    @State private var showSuccess = false
    @State private var uploadError: String? = nil
    @State private var importedCount = 0

    private func isValid(_ song: ImportableSong) -> Bool {
        !(song.songName ?? "").isEmpty &&
        !(song.artist ?? "").isEmpty &&
        !(song.originalKey ?? "").isEmpty &&
        !(song.content ?? "").isEmpty
    }

    var validSongs: [ImportableSong] { songs.filter(isValid) }
    var invalidSongs: [ImportableSong] { songs.filter { !isValid($0) } }

    var invalidCount: Int { songs.count - validSongs.count }

    /// Dosyadaki her şarkının kendine ait, tekrarsız bir docId'si varsa o ID'ler korunur.
    /// Aksi halde ID'ler sıra numarasından üretilir (dosyadaki sıra değişirse ID'ler de değişir).
    private var keepsFileDocIds: Bool {
        let ids = validSongs.compactMap { $0.docId?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return !ids.isEmpty && ids.count == validSongs.count && Set(ids).count == ids.count
    }

    var body: some View {
        NavigationStack {
            List {
                // Özet section
                Section {
                    HStack {
                        Image(systemName: "doc.badge.checkmark")
                            .foregroundColor(.green)
                        Text("\(validSongs.count) şarkı yüklenmeye hazır")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                    }
                    if invalidCount > 0 {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("\(invalidCount) şarkı eksik alan nedeniyle atlanacak")
                                .font(.system(size: 13))
                                .foregroundColor(.orange)
                        }
                    }
                    HStack {
                        Image(systemName: "icloud.and.arrow.up")
                            .foregroundColor(.secondary)
                        Text("Hedef: Firestore · songs (resmi katalog)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Yükleme Özeti")
                } footer: {
                    Text("Bu işlem dosyadaki şarkıları resmi kataloğa ekler; aynı ID'li kayıtların üzerine yazar, dosyada olmayan şarkılara dokunmaz. "
                         + (keepsFileDocIds
                            ? "Şarkı ID'leri dosyadaki docId alanından alınacak."
                            : "Şarkı ID'leri katalog sayacından yeni verilecek; mevcut şarkılar ve repertuarlar etkilenmez."))
                }

                // Şarkı listesi
                Section {
                    ForEach(Array(validSongs.enumerated()), id: \.offset) { _, song in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(song.songName ?? "—")
                                    .font(.system(size: 15, weight: .semibold))
                                Spacer()
                                Text(song.originalKey ?? "")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.blue.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                            Text(song.artist ?? "—")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Şarkılar (\(validSongs.count))")
                }

                // Geçersiz kayıtlar
                if invalidCount > 0 {
                    Section {
                        ForEach(Array(invalidSongs.enumerated()), id: \.offset) { _, song in
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                Text(song.songName ?? "(isimsiz)")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("Eksik alan")
                                    .font(.system(size: 12))
                                    .foregroundColor(.red)
                            }
                        }
                    } header: {
                        Text("Atlanacaklar")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollEdgeEffectStyle(.soft)
            .navigationTitle("Yüklenecekler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                        .disabled(isUploading)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        importToFirestore()
                    } label: {
                        if isUploading {
                            ProgressView()
                        } else {
                            Text("Onayla")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isUploading || validSongs.isEmpty)
                }
            }
            .overlay {
                if isUploading {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.4)
                            Text("Firestore'a yazılıyor…")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .padding(28)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                }
            }
            .alert("Yükleme Tamamlandı ✅", isPresented: $showSuccess) {
                Button("Tamam") { dismiss() }
            } message: {
                Text("\(importedCount) şarkı resmi kataloğa yazıldı.\nUygulama yeni şarkıları şimdi alıyor; web için `npm run publish` çalıştırın.")
            }
            .alert("Yükleme Hatası", isPresented: Binding(
                get: { uploadError != nil },
                set: { if !$0 { uploadError = nil } }
            )) {
                Button("Tamam") { uploadError = nil }
            } message: {
                Text(uploadError ?? "")
            }
        }
    }

    // MARK: - Import (Firestore)

    private func importToFirestore() {
        isUploading = true
        let importerName = authViewModel.userProfile?.username ?? authViewModel.displayName
        let keepFileDocIds = keepsFileDocIds
        let songsToImport = validSongs

        Task { @MainActor in
            do {
                let written = try await Self.writeSongs(songsToImport, keepFileDocIds: keepFileDocIds, importerName: importerName)
                await ChordsStorageManager.shared.checkForUpdates(force: true)
                importedCount = written
                isUploading = false
                showSuccess = true
            } catch {
                isUploading = false
                uploadError = error.localizedDescription
            }
        }
    }

    /// 1) `catalog/meta.seq` üzerinde `songs.count` kadar aralık ayırır (transaction),
    /// 2) her şarkıya bu aralıktan bir `seq`, gerekiyorsa yeni bir id ve slug verir,
    /// 3) 450'lik batch'lerle `songs/{id}` dokümanlarını `merge: true` ile yazar.
    @MainActor
    private static func writeSongs(_ songs: [ImportableSong], keepFileDocIds: Bool, importerName: String) async throws -> Int {
        guard !songs.isEmpty else { return 0 }
        let db = Firestore.firestore()
        let metaRef = db.collection("catalog").document("meta")
        let count = songs.count
        // Sayaç cihazdaki katalogun gerisine düşmesin (catalog/meta henüz yoksa 0 okunur).
        let floorSeq = ChordsStorageManager.shared.lastSeq

        let reserved = try await db.runTransaction { transaction, errorPointer -> Any? in
            let meta: DocumentSnapshot
            do {
                meta = try transaction.getDocument(metaRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }
            let current = max((meta.data()?["seq"] as? NSNumber)?.intValue ?? 0, floorSeq)
            transaction.setData(
                ["seq": current + count, "publishedAt": FieldValue.serverTimestamp()],
                forDocument: metaRef,
                merge: true
            )
            return current
        }
        guard let startSeq = reserved as? Int else {
            throw NSError(domain: "JSONImport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Katalog sayacı ayrılamadı."])
        }

        var allocator = SlugAllocator(existing: ChordsStorageManager.shared.slugMap)
        var batch = db.batch()
        var inBatch = 0

        for (index, song) in songs.enumerated() {
            let seq = startSeq + index + 1
            let id = keepFileDocIds
                ? (song.docId ?? "").trimmingCharacters(in: .whitespaces)
                : String(seq)
            let artist = (song.artist ?? "").trimmingCharacters(in: .whitespaces)
            let name = (song.songName ?? "").trimmingCharacters(in: .whitespaces)
            let slugs = allocator.allocate(id: id, artist: artist, songName: name)

            var data: [String: Any] = [
                "artist": artist,
                "songName": name,
                "originalKey": (song.originalKey ?? "").trimmingCharacters(in: .whitespaces),
                "content": song.content ?? "",
                "artistSlug": slugs.artistSlug,
                "slug": slugs.slug,
                "status": "approved",
                "deleted": false,
                "seq": seq,
                "addedBy": importerName,
                "updatedAt": FieldValue.serverTimestamp(),
            ]
            // Yeni id verilen kayıtlar kesinlikle yenidir; dosyadan gelen id'lerde createdAt'e dokunulmaz.
            if !keepFileDocIds { data["createdAt"] = FieldValue.serverTimestamp() }

            batch.setData(data, forDocument: db.collection("songs").document(id), merge: true)
            inBatch += 1
            if inBatch == 450 {
                try await batch.commit()
                batch = db.batch()
                inBatch = 0
            }
        }
        if inBatch > 0 { try await batch.commit() }
        return count
    }
}
