import Foundation
import FirebaseCore
import FirebaseStorage
import Combine

// MARK: - Download State

/// Firebase Storage'dan chords_data.json indirme durumu.
enum ChordsDownloadState: Equatable {
    /// Henüz başlamadı (uygulama henüz tetiklemedi)
    case idle
    /// Arka planda indirme devam ediyor
    case downloading
    /// İndirme tamamlandı, şarkılar belleğe yüklendi
    case ready
    /// İndirme veya decode hatası
    case failed(String)

    static func == (lhs: ChordsDownloadState, rhs: ChordsDownloadState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.downloading, .downloading), (.ready, .ready): return true
        case (.failed(let a), .failed(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - ChordsStorageManager

/// Firebase Storage'daki "chords/chords_data.json" dosyasını yöneten singleton.
///
/// ### Kullanım
/// ```swift
/// // App launch'ta arka plana al:
/// ChordsStorageManager.shared.startIfNeeded()
///
/// // SwiftUI'de gözlemle:
/// @StateObject var chordsManager = ChordsStorageManager.shared
/// ```
///
/// ### Tasarım Kararları
/// - Dosya cihazda zaten varsa hiç indirme yapmaz (`FileManager` kontrolü).
/// - Dosya eksikse Firebase Storage'dan arka planda indirir; UI asla bloklanmaz.
/// - `state` değişkeni `@Published` olduğundan SwiftUI otomatik tepki verir.
/// - `songs` dizisi decode edilmiş şarkıları tutar; dışarıdan sadece okunur.
@MainActor
final class ChordsStorageManager: ObservableObject {

    // MARK: - Singleton

    static let shared = ChordsStorageManager()
    private init() {}

    // MARK: - Published State

    /// İndirme durumu — SwiftUI ekranları bunu dinler.
    @Published private(set) var state: ChordsDownloadState = .idle

    /// Decode edilmiş şarkı listesi — state == .ready olduğunda dolucaktır.
    @Published private(set) var songs: [LocalSong] = []

    // MARK: - Private

    private let storagePath = "chords/chords_data.json"
    private let cacheFileName = "chords_data_storage.json"
    private var isStarted = false

    // MARK: - Cache URL

    /// @MainActor context içinde kullan (startIfNeeded, forceRedownload vb.)
    private var cacheFileURL: URL { makeCacheFileURL() }

    /// nonisolated — Task.detached bloklarından güvenle çağrılır.
    private nonisolated func makeCacheFileURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(cacheFileName)
    }

    // MARK: - Public API

    /// Uygulama açılışında çağrılır.
    /// - Dosya cihazda varsa sadece decode eder (ağ isteği yok).
    /// - Dosya yoksa arka planda Firebase Storage'dan indirir.
    /// İkinci çağrıda sessizce çıkar (idempotent).
    func startIfNeeded() {
        guard !isStarted else {
            print("🔵 ChordsStorageManager: startIfNeeded() atlandı — zaten başlatıldı.")
            return
        }
        isStarted = true
        print("🔵 ChordsStorageManager: startIfNeeded() tetiklendi. State: \(state)")
        print("   Cache path: \(cacheFileURL.path)")

        if FileManager.default.fileExists(atPath: cacheFileURL.path) {
            let size = (try? FileManager.default.attributesOfItem(atPath: cacheFileURL.path)[.size] as? Int) ?? 0
            print("📦 ChordsStorageManager: Cache mevcut (\(size / 1024) KB), disk'ten yükleniyor…")
            loadFromDisk()
        } else {
            print("⬇️ ChordsStorageManager: Cache yok. Firebase Storage'dan indiriliyor…")
            print("   Storage path: \(storagePath)")
            state = .downloading
            Task.detached(priority: .background) { [weak self] in
                await self?.downloadFromStorage()
            }
        }
    }

    /// Zorla yeniden indir (örn. pull-to-refresh veya admin butonu).
    func forceRedownload() {
        print("🔄 ChordsStorageManager: forceRedownload() tetiklendi.")
        isStarted = false
        try? FileManager.default.removeItem(at: cacheFileURL)
        songs = []
        state = .idle
        startIfNeeded()
    }

    // MARK: - Private: Disk Load

    private func loadFromDisk() {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let url = self.makeCacheFileURL()   // nonisolated → await gerekmez
            do {
                let data = try Data(contentsOf: url)
                let decoded = try Self.decodeSongs(from: data)  // nonisolated static
                await MainActor.run {
                    self.songs = decoded
                    self.state = .ready
                    print("✅ ChordsStorageManager: \(decoded.count) şarkı diskten yüklendi.")
                }
            } catch {
                await MainActor.run {
                    // Bozuk cache → sil ve yeniden indir
                    try? FileManager.default.removeItem(at: url)
                    self.isStarted = false
                    self.startIfNeeded()
                    print("⚠️ ChordsStorageManager: Disk decode hatası, yeniden indiriliyor: \(error)")
                }
            }
        }
    }

    // MARK: - Private: Firebase Storage Download

    /// nonisolated → Task.detached (background) içinden MainActor'a geçmeden çağrılabilir.
    private nonisolated func downloadFromStorage() async {
        let url = makeCacheFileURL()
        print("⬇️ ChordsStorageManager: Storage indirme başlıyor…")
        print("   Path: gs://\(Storage.storage().reference().bucket)/\(storagePath)")

        let storageRef = Storage.storage().reference(withPath: storagePath)

        do {
            // ---- 1. İndir ----
            let data = try await storageRef.data(maxSize: 50 * 1024 * 1024)
            print("📥 ChordsStorageManager: \(data.count) byte indirildi.")

            // ---- 2. Decode et ----
            let decoded: [LocalSong]
            do {
                decoded = try Self.decodeSongs(from: data)
                print("🎵 ChordsStorageManager: \(decoded.count) şarkı decode edildi.")
            } catch {
                // Ham JSON'ın ilk 300 karakterini logla — key uyuşmazlığını görmek için
                let preview = String(data: data.prefix(300), encoding: .utf8) ?? "<binary>"
                print("❌ ChordsStorageManager: JSON decode hatası: \(error)")
                print("   JSON preview: \(preview)")
                await MainActor.run {
                    self.state = .failed("JSON decode hatası: \(error.localizedDescription)")
                }
                return
            }

            // ---- 3. Diske kaydet ----
            do {
                try data.write(to: url, options: .atomic)
                print("💾 ChordsStorageManager: \(data.count / 1024) KB diske yazıldı → \(url.lastPathComponent)")
            } catch {
                print("⚠️ ChordsStorageManager: Diske yazma hatası (cache atlandı): \(error)")
            }

            // ---- 4. State güncelle ----
            await MainActor.run {
                self.songs = decoded
                self.state = .ready
                print("✅ ChordsStorageManager: Hazır! \(decoded.count) resmi şarkı yüklendi.")
            }

        } catch {
            // Firebase Storage NSError — hata kodunu göster
            let nsErr = error as NSError
            print("❌ ChordsStorageManager: Storage indirme hatası!")
            print("   Domain : \(nsErr.domain)")
            print("   Code   : \(nsErr.code)")
            print("   Message: \(nsErr.localizedDescription)")
            await MainActor.run {
                self.state = .failed("[\(nsErr.code)] \(nsErr.localizedDescription)")
            }
        }
    }

    // MARK: - Private: Decode

    /// JSON'daki kısa key'leri (a, s, k, c, i) `LocalSong` modeline decode eder.
    /// `static` + `nonisolated` → herhangi bir thread'den çağrılabilir, actor hop gerekmez.
    private nonisolated static func decodeSongs(from data: Data) throws -> [LocalSong] {
        let decoder = JSONDecoder()
        return try decoder.decode([LocalSong].self, from: data)
    }
}
