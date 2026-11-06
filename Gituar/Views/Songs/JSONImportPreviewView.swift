import SwiftUI

// MARK: - JSONImportPreviewView
//
// JSON dosyasından parse edilen şarkıları listeler (yalnızca yönetici).
// "Onayla" ile her şarkı Gituar API'sine (`POST /v1/songs`) gönderilir; yöneticinin gönderdiği şarkı
// doğrudan yayına girer. Kimlik ve slug'ları sunucu verir.

struct JSONImportPreviewView: View {
    let songs: [ImportableSong]
    let rawData: Data

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authViewModel: AuthViewModel

    @State private var isUploading = false
    @State private var showSuccess = false
    @State private var uploadError: String? = nil
    @State private var importedCount = 0
    @State private var failedCount = 0
    @State private var progress = 0

    private func isValid(_ song: ImportableSong) -> Bool {
        !(song.songName ?? "").isEmpty &&
        !(song.artist ?? "").isEmpty &&
        !(song.originalKey ?? "").isEmpty &&
        !(song.content ?? "").isEmpty
    }

    var validSongs: [ImportableSong] { songs.filter(isValid) }
    var invalidSongs: [ImportableSong] { songs.filter { !isValid($0) } }

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
                        Text("Hedef: Gituar API · yayında")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Yükleme Özeti")
                } footer: {
                    Text("Bu işlem dosyadaki her şarkıyı yeni bir şarkı olarak ekler ve yayına alır. Mevcut şarkılara dokunulmaz; şarkı kimliklerini sunucu verir.")
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
                        importToAPI()
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
                            Text("Gönderiliyor… \(progress)/\(validSongs.count)")
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
                Text(failedCount > 0
                     ? "\(importedCount) şarkı eklendi, \(failedCount) şarkı eklenemedi."
                     : "\(importedCount) şarkı eklendi ve yayına alındı.")
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

    // MARK: - Import (API)

    private func importToAPI() {
        isUploading = true
        progress = 0
        let importerName = authViewModel.userProfile?.username ?? authViewModel.displayName
        let songsToImport = validSongs

        Task {
            var ok = 0
            var failed = 0
            var lastError: String?
            for song in songsToImport {
                let input = GituarAPI.SongInput(
                    artist: (song.artist ?? "").trimmingCharacters(in: .whitespaces),
                    title: (song.songName ?? "").trimmingCharacters(in: .whitespaces),
                    originalKey: (song.originalKey ?? "").trimmingCharacters(in: .whitespaces),
                    content: song.content ?? "",
                    status: "pending",
                    addedBy: importerName
                )
                do {
                    _ = try await GituarAPI.shared.createSong(input)
                    ok += 1
                } catch GituarAPIError.offline {
                    lastError = GituarAPIError.offline.localizedDescription
                    failed += songsToImport.count - ok - failed
                    break
                } catch {
                    failed += 1
                    lastError = error.localizedDescription
                }
                progress = ok + failed
            }
            isUploading = false
            importedCount = ok
            failedCount = failed
            if ok == 0, let lastError {
                uploadError = lastError
            } else {
                showSuccess = true
            }
        }
    }
}
