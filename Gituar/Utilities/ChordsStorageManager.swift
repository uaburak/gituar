import Foundation
import Combine
import FirebaseFirestore

// MARK: - Download State

/// Resmi katalogun yüklenme durumu.
enum ChordsDownloadState: Equatable {
    /// Henüz başlamadı
    case idle
    /// Paketteki seed açılıyor / ilk yükleme sürüyor
    case downloading
    /// Katalog bellekte, fark senkronu arka planda
    case ready
    /// Seed okunamadı
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

/// Resmi şarkı kataloğu: uygulamaya gömülü seed (`Resources/catalog.deflate`) + Firestore fark senkronu.
///
/// ### Akış
/// 1. Açılışta cihazdaki birleşik kopya (varsa) ya da paketteki seed açılır → `songs` anında hazır.
/// 2. Firestore `songs` koleksiyonundan `seq > lastSeq` olan dokümanlar çekilir (500'lük sayfalar),
///    `deleted == true` olanlar çıkarılır, kalanlar üzerine yazılır, birleşik kopya diske yazılır.
/// 3. Değişiklik yoksa sorgu 0 doküman döner; Firestore okuma saymaz.
///
/// Kullanıcı istemcisi kataloğu bunun dışında hiçbir yerden okumaz. Biçim: docs/PLATFORM-PLAN.md §4.
@MainActor
final class ChordsStorageManager: ObservableObject {

    // MARK: - Singleton

    static let shared = ChordsStorageManager()
    private init() {}

    // MARK: - Published State

    @Published private(set) var state: ChordsDownloadState = .idle
    @Published private(set) var songs: [LocalSong] = []

    /// Son uygulanan değişiklik sayacı (`catalog/meta.seq` ile karşılaştırılır).
    private(set) var lastSeq: Int = 0

    // MARK: - Private

    private let db = Firestore.firestore()
    private let cacheFileName = "catalog_cache.deflate"
    private let bundleBuildKey = "catalog.bundleBuild"
    private let cacheSeqKey = "catalog.cacheSeq"

    /// id → kayıt (silinmişler dahil; fark senkronu silmeyi de taşır)
    private var records: [String: CatalogSongRecord] = [:]
    private var isStarted = false
    private var isSyncing = false
    private var lastSyncCheck: Date?
    /// Otomatik fark kontrolleri arasındaki en kısa süre (pull-to-refresh `force` ile bunu atlar).
    private let syncInterval: TimeInterval = 6 * 60 * 60
    private let pageSize = 500

    // MARK: - Paths

    private nonisolated func makeCacheFileURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(cacheFileName)
    }

    private nonisolated static var bundledSeedURL: URL? {
        Bundle.main.url(forResource: "catalog", withExtension: "deflate")
    }

    private nonisolated static var currentBuild: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0")
            + "-" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0")
    }

    // MARK: - Public API

    /// Uygulama açılışında çağrılır. İkinci çağrıda sessizce çıkar.
    func startIfNeeded() {
        guard !isStarted else { return }
        isStarted = true
        state = .downloading
        print("🔵 ChordsStorageManager: seed yükleniyor…")

        let cacheURL = makeCacheFileURL()
        let defaults = UserDefaults.standard
        let cachedSeq = defaults.integer(forKey: cacheSeqKey)
        let buildChanged = defaults.string(forKey: bundleBuildKey) != Self.currentBuild

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            var snapshot: CatalogSnapshot?
            var source = "cache"

            // 1. Cihazdaki birleşik kopya
            if FileManager.default.fileExists(atPath: cacheURL.path) {
                snapshot = try? Self.loadSnapshot(from: cacheURL)
                if snapshot == nil { try? FileManager.default.removeItem(at: cacheURL) }
            }

            // 2. Paketteki seed: kopya yoksa, ya da uygulama güncellendi ve seed daha yeniyse
            if snapshot == nil || buildChanged, let seedURL = Self.bundledSeedURL {
                if let seed = try? Self.loadSnapshot(from: seedURL) {
                    if snapshot == nil || seed.seq > (snapshot?.seq ?? cachedSeq) {
                        snapshot = seed
                        source = "bundle"
                    }
                }
            }

            guard let snapshot else {
                await MainActor.run {
                    self.state = .failed("Katalog seed'i okunamadı.")
                    print("❌ ChordsStorageManager: ne cache ne seed okunabildi.")
                }
                return
            }

            await self.apply(snapshot: snapshot, source: source, persist: source == "bundle")
            await self.syncDelta(force: true)
        }
    }

    /// Seed okunamadıysa yeniden dener.
    func retryIfFailed() {
        guard case .failed = state else { return }
        isStarted = false
        state = .idle
        startIfNeeded()
    }

    /// Firestore'dan `seq > lastSeq` olan farkları çeker.
    /// - Parameter force: true ise son kontrolün üzerinden geçen süreye bakılmaz (pull-to-refresh).
    func checkForUpdates(force: Bool = false) async {
        await syncDelta(force: force)
    }

    /// Diskteki kopyayı atar, paketteki seed'den yeniden başlar ve farkları baştan çeker.
    func forceRedownload() {
        print("🔄 ChordsStorageManager: forceRedownload()")
        try? FileManager.default.removeItem(at: makeCacheFileURL())
        UserDefaults.standard.removeObject(forKey: cacheSeqKey)
        isStarted = false
        records = [:]
        songs = []
        lastSeq = 0
        lastSyncCheck = nil
        state = .idle
        startIfNeeded()
    }

    /// Mevcut (silinmemiş) şarkıların id → (artistSlug, slug) eşlemesi; içe aktarmada URL kalıcılığı için.
    var slugMap: [String: (artistSlug: String, slug: String)] {
        var map: [String: (artistSlug: String, slug: String)] = [:]
        for (id, r) in records where !r.isDeleted { map[id] = (r.artistSlug, r.slug) }
        return map
    }

    // MARK: - Admin API

    /// Resmi bir şarkıyı siler: `catalog/meta.seq` artar, `songs/{id}` `deleted: true` + yeni seq alır.
    /// Yalnızca Firestore kurallarında admin olan kullanıcılar yapabilir.
    func deleteOfficialSong(songId: String) async throws {
        print("🗑️ ChordsStorageManager: deleteOfficialSong(\(songId))")
        let metaRef = db.collection("catalog").document("meta")
        let songRef = db.collection("songs").document(songId)
        // catalog/meta henüz yoksa ya da gerideyse sayaç cihazdaki katalogdan geri gitmesin;
        // aksi halde yeni seq, seed'in seq'inden küçük kalır ve hiçbir cihaz farkı görmez.
        let floorSeq = lastSeq

        let result = try await db.runTransaction { transaction, errorPointer -> Any? in
            let meta: DocumentSnapshot
            do {
                meta = try transaction.getDocument(metaRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }
            let current = max((meta.data()?["seq"] as? NSNumber)?.intValue ?? 0, floorSeq)
            let newSeq = current + 1
            transaction.setData(["seq": newSeq, "publishedAt": FieldValue.serverTimestamp()], forDocument: metaRef, merge: true)
            // merge yok: dokümandaki söz/akor/ad alanları da silinir; yalnızca içeriksiz silme kaydı kalır
            transaction.setData(["deleted": true, "seq": newSeq, "updatedAt": FieldValue.serverTimestamp()], forDocument: songRef)
            return newSeq
        }
        guard let newSeq = result as? Int else {
            throw NSError(domain: "ChordsStorageManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Katalog sayacı güncellenemedi."])
        }

        // Yerelde uygula: içerik cihazda da tutulmaz
        if var record = records[songId] {
            record.deleted = true
            record.seq = newSeq
            record.artist = ""
            record.songName = ""
            record.originalKey = ""
            record.content = ""
            record.artistSlug = ""
            record.slug = ""
            record.createdAt = nil
            record.addedBy = nil
            records[songId] = record
        }
        // Şarkıya bağlı sayaç dokümanları
        try? await db.collection("song-metrics").document(songId).delete()
        try? await db.collection("chords").document(songId).delete()
        lastSeq = max(lastSeq, newSeq)
        publishSongs()
        persistToDisk()
        print("✅ ChordsStorageManager: \(songId) silindi, seq=\(newSeq).")
    }

    // MARK: - Private: apply / publish / persist

    private func apply(snapshot: CatalogSnapshot, source: String, persist: Bool) {
        var map: [String: CatalogSongRecord] = [:]
        map.reserveCapacity(snapshot.songs.count)
        for r in snapshot.songs { map[r.id] = r }
        records = map
        lastSeq = snapshot.seq
        publishSongs()
        state = .ready
        UserDefaults.standard.set(Self.currentBuild, forKey: bundleBuildKey)
        print("✅ ChordsStorageManager: \(songs.count) şarkı \(source)'dan yüklendi (seq \(snapshot.seq)).")
        if persist { persistToDisk() }
    }

    private func publishSongs() {
        songs = records.values
            .filter { !$0.isDeleted }
            .sorted { $0.seq < $1.seq }
            .map { $0.toLocalSong() }
    }

    private func persistToDisk() {
        let snapshot = CatalogSnapshot(
            seq: lastSeq,
            count: records.values.filter { !$0.isDeleted }.count,
            publishedAt: ISO8601DateFormatter().string(from: Date()),
            songs: records.values.sorted { $0.seq < $1.seq }
        )
        let url = makeCacheFileURL()
        let seq = lastSeq
        Task.detached(priority: .utility) {
            do {
                try Self.saveSnapshot(snapshot, to: url)
                UserDefaults.standard.set(seq, forKey: "catalog.cacheSeq")
            } catch {
                print("⚠️ ChordsStorageManager: diske yazılamadı: \(error)")
            }
        }
    }

    // MARK: - Private: delta sync

    private func syncDelta(force: Bool) async {
        guard state == .ready, !isSyncing else { return }
        if !force, let lastSyncCheck, Date().timeIntervalSince(lastSyncCheck) < syncInterval { return }
        isSyncing = true
        defer { isSyncing = false }

        var changes: [CatalogSongRecord] = []
        var cursor = lastSeq
        do {
            while true {
                let page = try await db.collection("songs")
                    .whereField("seq", isGreaterThan: cursor)
                    .order(by: "seq")
                    .limit(to: pageSize)
                    .getDocuments()
                for doc in page.documents {
                    guard let record = Self.record(from: doc) else { continue }
                    changes.append(record)
                    cursor = max(cursor, record.seq)
                }
                if page.documents.count < pageSize { break }
            }
            lastSyncCheck = Date()
        } catch {
            print("⚠️ ChordsStorageManager: fark senkronu başarısız: \(error.localizedDescription)")
            return
        }

        guard !changes.isEmpty else {
            print("✅ ChordsStorageManager: katalog güncel (seq \(lastSeq)).")
            return
        }
        for change in changes { records[change.id] = change }
        lastSeq = cursor
        publishSongs()
        persistToDisk()
        print("✅ ChordsStorageManager: \(changes.count) değişiklik uygulandı → seq \(lastSeq), \(songs.count) şarkı.")
    }

    private nonisolated static func record(from doc: QueryDocumentSnapshot) -> CatalogSongRecord? {
        let d = doc.data()
        guard let seq = (d["seq"] as? NSNumber)?.intValue else { return nil }
        var createdAt: String?
        if let ts = d["createdAt"] as? Timestamp {
            createdAt = ISO8601DateFormatter().string(from: ts.dateValue())
        } else if let s = d["createdAt"] as? String {
            createdAt = s
        }
        return CatalogSongRecord(
            id: doc.documentID,
            artist: d["artist"] as? String ?? "",
            songName: d["songName"] as? String ?? "",
            originalKey: d["originalKey"] as? String ?? "",
            content: d["content"] as? String ?? "",
            artistSlug: d["artistSlug"] as? String ?? "",
            slug: d["slug"] as? String ?? "",
            seq: seq,
            createdAt: createdAt,
            addedBy: d["addedBy"] as? String,
            deleted: (d["deleted"] as? Bool) == true ? true : nil
        )
    }

    // MARK: - Private: deflate I/O

    /// Ham DEFLATE (zlib başlıksız) → JSON → CatalogSnapshot. Node tarafı `zlib.deflateRawSync` ile üretir.
    private nonisolated static func loadSnapshot(from url: URL) throws -> CatalogSnapshot {
        let compressed = try Data(contentsOf: url, options: .mappedIfSafe)
        let json = try (compressed as NSData).decompressed(using: .zlib) as Data
        return try JSONDecoder().decode(CatalogSnapshot.self, from: json)
    }

    private nonisolated static func saveSnapshot(_ snapshot: CatalogSnapshot, to url: URL) throws {
        let json = try JSONEncoder().encode(snapshot)
        let compressed = try (json as NSData).compressed(using: .zlib) as Data
        try compressed.write(to: url, options: .atomic)
    }
}
