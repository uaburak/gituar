import SwiftUI
import FirebaseStorage

// MARK: - JSONImportPreviewView
//
// JSON dosyasından parse edilen şarkıları listeler.
// "Onayla" butonuna basınca dosyayı Firebase Storage'a yükler:
//   gs://koc-chords.firebasestorage.app/chords/chords_data.json
// Yükleme tamamlanınca ChordsStorageManager yeniden indirir.

struct JSONImportPreviewView: View {
    let songs: [ImportableSong]
    let rawData: Data

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authViewModel: AuthViewModel

    @State private var isUploading = false
    @State private var showSuccess = false
    @State private var uploadError: String? = nil

    private let storagePath = "chords/chords_data.json"

    var validSongs: [ImportableSong] {
        songs.filter {
            !($0.songName ?? "").isEmpty &&
            !($0.artist ?? "").isEmpty &&
            !($0.originalKey ?? "").isEmpty &&
            !($0.content ?? "").isEmpty
        }
    }

    var invalidCount: Int { songs.count - validSongs.count }

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
                        Text("Hedef: chords/chords_data.json")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Yükleme Özeti")
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
                        ForEach(Array(songs.filter {
                            ($0.songName ?? "").isEmpty ||
                            ($0.artist ?? "").isEmpty ||
                            ($0.originalKey ?? "").isEmpty ||
                            ($0.content ?? "").isEmpty
                        }.enumerated()), id: \.offset) { _, song in
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
            .navigationTitle("Yüklenecekler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                        .disabled(isUploading)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        uploadToStorage()
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
                            Text("Firebase Storage'a yükleniyor…")
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
                Text("\(validSongs.count) şarkı başarıyla Storage'a yüklendi.\nUygulama yeni şarkıları kısa sürede gösterecek.")
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

    // MARK: - Upload

    private func uploadToStorage() {
        isUploading = true

        // LocalSong formatıyla uyumlu encode (docId, artist, songName, originalKey, content, addedBy)
        struct UploadSong: Encodable {
            let docId: String
            let artist: String
            let songName: String
            let originalKey: String
            let content: String
            let addedBy: String
        }

        let importerName = authViewModel.userProfile?.username ?? authViewModel.displayName

        let uploadSongs = validSongs.enumerated().map { idx, song in
            UploadSong(
                docId: "\(idx + 1)",
                artist: song.artist ?? "",
                songName: song.songName ?? "",
                originalKey: song.originalKey ?? "",
                content: song.content ?? "",
                addedBy: importerName
            )
        }

        guard let uploadData = try? JSONEncoder().encode(uploadSongs) else {
            isUploading = false
            uploadError = "Veri encode edilemedi."
            return
        }

        let metadata = StorageMetadata()
        metadata.contentType = "application/json"

        let storageRef = Storage.storage().reference(withPath: storagePath)
        storageRef.putData(uploadData, metadata: metadata) { _, error in
            DispatchQueue.main.async {
                isUploading = false
                if let error = error {
                    uploadError = error.localizedDescription
                } else {
                    ChordsStorageManager.shared.forceRedownload()
                    showSuccess = true
                }
            }
        }
    }
}
