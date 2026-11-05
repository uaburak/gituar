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
    private let pendingWritesFile   = "pending_writes.json"
    private let songsCacheFile      = "songs_cache.json"

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
            // Delete corrupted cache; the next sync rewrites it
            try? FileManager.default.removeItem(at: url)
            return nil
        }
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

    var hasPendingWrites: Bool {
        !loadPendingWrites().isEmpty
    }

    // MARK: - Flush Pending Writes

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

        print("✅ SyncManager: Flush complete. \(flushedIds.count) succeeded, \(remaining.count) remaining.")
    }

    // MARK: - Full Sync (user-chords only)

    /// Fetches ONLY the user-chords collection from Firestore and updates the local cache.
    /// Official/system songs are loaded from Firebase Storage via ChordsStorageManager.
    func performFullSync(collectionUserChords: String) async throws -> [Song] {
        print("🔄 SyncManager: Syncing user-chords from Firestore…")

        let userSnap = try await db.collection(collectionUserChords).getDocuments()

        var userSongs: [Song] = []
        for doc in userSnap.documents {
            if var song = try? doc.data(as: Song.self) {
                // Eğer docId boşsa Firestore döküman ID'sini fallback olarak kullan
                if song.docId.isEmpty {
                    song.docId = doc.documentID
                    print("⚠️ SyncManager: docId eksikti, döküman ID kullanıldı: \(doc.documentID)")
                }
                userSongs.append(song)
            } else {
                // Decode başarısız — ham veriyi kullanarak manuel Song oluştur
                let data = doc.data()
                let docId = doc.documentID
                let artist = data["artist"] as? String ?? ""
                let songName = data["songName"] as? String ?? ""
                let originalKey = data["originalKey"] as? String ?? ""
                let content = data["content"] as? String ?? ""
                let ownerId = data["ownerId"] as? String
                let addedBy = data["addedBy"] as? String
                let status = data["status"] as? String

                guard !artist.isEmpty || !songName.isEmpty else {
                    print("❌ SyncManager: \(docId) decode edilemedi ve yeterli alan yok, atlanıyor.")
                    continue
                }

                let fallbackSong = Song(
                    docId: docId,
                    artist: artist,
                    songName: songName,
                    originalKey: originalKey,
                    content: content,
                    ownerId: ownerId,
                    addedBy: addedBy,
                    status: status
                )
                userSongs.append(fallbackSong)
                print("⚠️ SyncManager: \(docId) manuel fallback ile yüklendi.")
            }
        }

        // Only cache user-chords — official songs don't need caching here
        saveSongsToCache(userSongs)

        print("✅ SyncManager: Sync complete. \(userSongs.count) user songs fetched from Firestore.")
        return userSongs
    }
}
