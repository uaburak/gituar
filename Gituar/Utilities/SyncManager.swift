import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - PendingWrite

/// Represents a single deferred Firestore write operation.
struct PendingWrite: Codable {
    enum Operation: String, Codable {
        case set, update, delete
    }
    var id: String = UUID().uuidString
    var collection: String
    var documentId: String
    var operation: Operation
    /// JSON-encoded fields for set/update. Nil for delete.
    var fields: [String: CodableValue]?
}

// MARK: - CodableValue (Firestore field wrapper)

enum CodableValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(String.self)  { self = .string(v); return }
        if let v = try? c.decode(Bool.self)    { self = .bool(v);   return }
        if let v = try? c.decode(Int.self)     { self = .int(v);    return }
        if let v = try? c.decode(Double.self)  { self = .double(v); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v):    try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v):   try c.encode(v)
        case .null:          try c.encodeNil()
        }
    }

    /// Convert to a value Firestore's `updateData` / `setData` can accept.
    var firestoreValue: Any {
        switch self {
        case .string(let v): return v
        case .int(let v):    return v
        case .double(let v): return v
        case .bool(let v):   return v
        case .null:          return NSNull()
        }
    }
}

// MARK: - SyncManager

@MainActor
final class SyncManager {

    static let shared = SyncManager()

    // MARK: Keys
    private let lastSyncKey         = "gtr_last_full_sync"
    private let lastWriteFlushKey   = "gtr_last_write_flush"
    private let pendingWritesFile   = "pending_writes.json"
    private let songsCacheFile      = "songs_cache.json"

    // 24-hour interval
    private let syncInterval: TimeInterval = 86_400

    private let db = Firestore.firestore()

    // MARK: - Shared JSON helpers (ISO8601 dates)
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Cache helpers

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func cacheURL(_ filename: String) -> URL {
        documentsURL.appendingPathComponent(filename)
    }

    // MARK: - Songs Cache

    /// Saves songs to local JSON cache.
    /// - Returns: true if write succeeded, false otherwise.
    @discardableResult
    func saveSongsToCache(_ songs: [Song]) -> Bool {
        do {
            let data = try encoder.encode(songs)
            try data.write(to: cacheURL(songsCacheFile), options: .atomic)
            print("💾 SyncManager: Cache saved (\(songs.count) songs, \(data.count / 1024)KB)")
            return true
        } catch {
            print("❌ SyncManager: Failed to save songs cache: \(error)")
            return false
        }
    }

    func loadSongsFromCache() -> [Song]? {
        let url = cacheURL(songsCacheFile)
        guard let data = try? Data(contentsOf: url) else {
            print("⚠️ SyncManager: Cache file not found at \(url.lastPathComponent)")
            return nil
        }
        do {
            let songs = try decoder.decode([Song].self, from: data)
            print("📦 SyncManager: Loaded \(songs.count) songs from cache")
            return songs
        } catch {
            print("❌ SyncManager: Cache decode failed: \(error) — will force sync")
            // Delete corrupted cache so next launch re-syncs
            try? FileManager.default.removeItem(at: url)
            UserDefaults.standard.removeObject(forKey: lastSyncKey)
            return nil
        }
    }

    // MARK: - Diagnostics helpers (used by SyncTestView)

    var cacheFileURL: URL { cacheURL(songsCacheFile) }

    var cacheFileExists: Bool {
        FileManager.default.fileExists(atPath: cacheURL(songsCacheFile).path)
    }

    var cacheFileSizeKB: Int {
        let size = (try? FileManager.default.attributesOfItem(atPath: cacheURL(songsCacheFile).path)[.size] as? Int) ?? 0
        return size / 1024
    }

    func isCacheStale() -> Bool {
        guard let last = UserDefaults.standard.object(forKey: lastSyncKey) as? Date else {
            return true // never synced
        }
        return Date().timeIntervalSince(last) >= syncInterval
    }

    func markSyncCompleted() {
        UserDefaults.standard.set(Date(), forKey: lastSyncKey)
    }

    /// Deletes local cache and timestamp → forces Firestore sync on next launch.
    func resetCache() {
        try? FileManager.default.removeItem(at: cacheURL(songsCacheFile))
        UserDefaults.standard.removeObject(forKey: lastSyncKey)
        print("🗑️ SyncManager: Cache reset — will force sync on next launch.")
    }

    // MARK: - Pending Writes Queue

    private func loadPendingWrites() -> [PendingWrite] {
        guard let data = try? Data(contentsOf: cacheURL(pendingWritesFile)) else { return [] }
        return (try? decoder.decode([PendingWrite].self, from: data)) ?? []
    }

    private func savePendingWrites(_ writes: [PendingWrite]) {
        guard let data = try? encoder.encode(writes) else { return }
        try? data.write(to: cacheURL(pendingWritesFile), options: .atomic)
    }

    func enqueuePendingWrite(_ write: PendingWrite) {
        var writes = loadPendingWrites()
        // Replace if same document + operation to avoid duplicates
        writes.removeAll { $0.collection == write.collection && $0.documentId == write.documentId && $0.operation == write.operation }
        writes.append(write)
        savePendingWrites(writes)
        print("📝 SyncManager: Enqueued \(write.operation.rawValue) for \(write.collection)/\(write.documentId)")
    }

    func removePendingWrite(id: String) {
        var writes = loadPendingWrites()
        writes.removeAll { $0.id == id }
        savePendingWrites(writes)
    }

    var hasPendingWrites: Bool {
        !loadPendingWrites().isEmpty
    }

    var pendingWriteCount: Int {
        loadPendingWrites().count
    }



    // MARK: - Flush Pending Writes

    func shouldFlushWrites() -> Bool {
        guard let last = UserDefaults.standard.object(forKey: lastWriteFlushKey) as? Date else {
            return hasPendingWrites
        }
        return hasPendingWrites && Date().timeIntervalSince(last) >= syncInterval
    }

    /// Flush all queued writes to Firestore.
    func flushPendingWrites() async {
        let writes = loadPendingWrites()
        guard !writes.isEmpty else { return }

        print("🚀 SyncManager: Flushing \(writes.count) pending write(s) to Firestore…")
        var flushedIds: [String] = []

        for write in writes {
            let ref = db.collection(write.collection).document(write.documentId)
            do {
                switch write.operation {
                case .set:
                    if let fields = write.fields {
                        let data = fields.mapValues { $0.firestoreValue }
                        try await ref.setData(data, merge: true)
                    }
                case .update:
                    if let fields = write.fields {
                        let data = fields.mapValues { $0.firestoreValue }
                        try await ref.updateData(data)
                    }
                case .delete:
                    try await ref.delete()
                }
                flushedIds.append(write.id)
                print("  ✅ Flushed \(write.operation.rawValue): \(write.collection)/\(write.documentId)")
            } catch {
                print("  ❌ Failed to flush \(write.collection)/\(write.documentId): \(error)")
            }
        }

        // Remove successfully flushed writes
        var remaining = loadPendingWrites()
        remaining.removeAll { flushedIds.contains($0.id) }
        savePendingWrites(remaining)

        if flushedIds.count > 0 {
            UserDefaults.standard.set(Date(), forKey: lastWriteFlushKey)
        }
        print("✅ SyncManager: Flush complete. \(flushedIds.count) succeeded, \(remaining.count) remaining.")
    }

    // MARK: - Bundle Songs

    /// Loads the bundled chords_data.json — zero Firestore reads, always fast.
    func loadBundleSongs() -> [Song] {
        guard let url = Bundle.main.url(forResource: "chords_data", withExtension: "json") else {
            print("⚠️ SyncManager: chords_data.json not found in bundle.")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            // Bundle JSON uses simple ISO8601 dates (or no dates); use a flexible decoder
            let bundleDecoder = JSONDecoder()
            bundleDecoder.dateDecodingStrategy = .iso8601
            let songs = try bundleDecoder.decode([Song].self, from: data)
            print("📦 SyncManager: Loaded \(songs.count) bundle songs from chords_data.json")
            return songs
        } catch {
            print("❌ SyncManager: Failed to decode chords_data.json: \(error)")
            return []
        }
    }

    // MARK: - Full Sync (user-chords only — official songs come from bundle)

    /// Fetches ONLY the user-chords collection from Firestore and updates the local cache.
    /// Official/system songs are always loaded from the bundled chords_data.json.
    func performFullSync(collectionChords: String, collectionUserChords: String) async throws -> [Song] {
        print("🔄 SyncManager: Syncing user-chords from Firestore (bundle songs are local)…")

        let userSnap = try await db.collection(collectionUserChords).getDocuments()
        let userSongs = userSnap.documents.compactMap { try? $0.data(as: Song.self) }

        // Only cache user-chords — bundle songs don't need caching
        let saved = saveSongsToCache(userSongs)
        if saved {
            markSyncCompleted()
        } else {
            print("⚠️ SyncManager: Cache write failed — sync timestamp NOT updated to force retry next launch")
        }

        print("✅ SyncManager: Sync complete. \(userSongs.count) user songs fetched from Firestore.")
        return userSongs
    }
}
