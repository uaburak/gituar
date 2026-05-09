import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine
import SwiftUI

// MARK: - ChordViewModel (Offline-First)

@MainActor
class ChordViewModel: ObservableObject {
    @Published var songs: [Song] = [] // Arama sonuçları
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    
    // Dashboard Verileri
    @Published var repertoires: [Repertoire] = []
    @Published var recentlyPlayed: [Song] = []
    @Published var mostAdded: [Song] = []
    @Published var popularChords: [Song] = []
    @Published var newArrivals: [Song] = []
    @Published var artists: [String] = [] // Sanatçı listesi
    @Published var allSongs: [Song] = [] // Tüm şarkılar (Cache)
    @Published var publicRepertoires: [Repertoire] = [] // Paylaşılan repertuarlar
    @Published var songPreferences: [String: UserSongPreference] = [:] // Kullanıcıya özel şarkı ayarları
    @Published var pendingSongs: [Song] = [] // Onay bekleyen şarkılar
    
    private let collectionChords = "chords"
    private let collectionUserChords = "user-chords"
    private let collectionPublicRepertoires = "public-repertoires"
    private let metadataCollection = "metadata"
    private let countersDocument = "counters"
    
    private var db = Firestore.firestore()
    private var cancellables = Set<AnyCancellable>()
    private var authListener: AuthStateDidChangeListenerHandle?
    
    private let recentPlayedKey = "recentlyPlayedIds"
    private let repertoiresKey = "user_repertoires"
    
    var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }
    
    private var userId: String? {
        Auth.auth().currentUser?.uid
    }

    /// Only the songs added by users (docId starts with "u" or "tmp_").
    /// Bundle/system songs are excluded — they don't need to be cached or synced.
    private var allUserSongs: [Song] {
        allSongs.filter { $0.docId.hasPrefix("u") || $0.docId.hasPrefix("tmp_") }
    }

    
    init() {
        setupAuthListener()
        fetchAllSongs()
        
        $searchText
            .debounce(for: .milliseconds(600), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] text in
                Task {
                    await self?.filterSongs(query: text)
                }
            }
            .store(in: &cancellables)
            
        fetchPublicRepertoires()
    }
    
    private func setupAuthListener() {
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.loadUserData(userId: user?.uid)
            }
        }
    }
    
    private func loadUserData(userId: String?) {
        songPreferences.removeAll()
        if let uid = userId {
            fetchRepertoiresFromFirestore(userId: uid)
        } else {
            // Guest mode or Logged out
            loadRepertoires()
        }
    }

    // MARK: - Bundle-First Song Loading

    private func fetchAllSongs() {
        guard !isLoading else { return }
        isLoading = true

        Task { @MainActor in
            let syncManager = SyncManager.shared

            // 1. Load system/official songs from bundle (zero Firestore reads, instant)
            let bundleSongs = syncManager.loadBundleSongs()
            print("📦 ChordViewModel: \(bundleSongs.count) songs loaded from bundle.")

            // 2. Load cached user-chords from disk (zero Firestore reads)
            let cachedUserSongs = syncManager.loadSongsFromCache() ?? []
            print("📦 ChordViewModel: \(cachedUserSongs.count) user songs loaded from cache.")

            // Merge: bundle songs + cached user songs
            self.allSongs = bundleSongs + cachedUserSongs
            self.isLoading = false
            self.processDashboardData()
            self.loadUserData(userId: self.userId)

            // 3. Sync user-chords from Firestore only if cache is stale (> 24 hours)
            if syncManager.isCacheStale() {
                print("🔄 ChordViewModel: User-chords cache stale – syncing from Firestore…")
                do {
                    let freshUserSongs = try await syncManager.performFullSync(
                        collectionChords: collectionChords,
                        collectionUserChords: collectionUserChords
                    )
                    // Re-merge with fresh user data
                    self.allSongs = bundleSongs + freshUserSongs
                    self.processDashboardData()
                    self.loadUserData(userId: self.userId)
                } catch {
                    print("❌ ChordViewModel: Firestore user-chords sync failed: \(error)")
                }
            } else {
                print("✅ ChordViewModel: User-chords cache is fresh – skipping Firestore read.")
            }

            // 4. Flush any pending writes once per day
            if syncManager.shouldFlushWrites() {
                await syncManager.flushPendingWrites()
            }
        }
    }

    /// Call this to force a fresh sync of user-chords from Firestore (e.g., pull-to-refresh).
    /// System songs are always from the bundle and don't need refreshing.
    func forceSync() {
        guard !isLoading else { return }
        isLoading = true
        Task { @MainActor in
            let syncManager = SyncManager.shared
            let bundleSongs = syncManager.loadBundleSongs()
            do {
                let freshUserSongs = try await syncManager.performFullSync(
                    collectionChords: collectionChords,
                    collectionUserChords: collectionUserChords
                )
                self.allSongs = bundleSongs + freshUserSongs
                self.processDashboardData()
                self.loadUserData(userId: self.userId)
            } catch {
                print("❌ ChordViewModel: forceSync failed: \(error)")
            }
            self.isLoading = false
        }
    }

    
    func fetchPendingSongs() {
        // Sadece bekleyenleri çek (Gerçek uygulamada sadece admin çekebilmeli ama şimdilik client-side da olabilir)
        // Ya da admin ise fetchPendingSongs() çağrılır.
        self.pendingSongs = allSongs.filter { $0.status == "pending" }
    }
    
    private func processDashboardData() {
        // Sadece onaylı şarkıları dashboard ve arama için kullan (status nil olan eski şarkıları da dahil ediyoruz)
        let approvedSongs = allSongs.filter { $0.status == "approved" || $0.status == nil }
        
        // Sanatçıları alfabetik listele
        self.artists = Array(Set(approvedSongs.map { $0.artist })).sorted()
        
        // En çok eklenenler (repertoireAdds'e göre)
        self.mostAdded = approvedSongs.sorted { ($0.repertoireAdds ?? 0) > ($1.repertoireAdds ?? 0) }.prefix(10).map { $0 }
        
        // Popülerler (Ağırlıklı Algoritma - popularityScore'a göre)
        // Score = (TotalViews * 0.1) + (RecentViews * 0.6) + (RepertoireAdds * 0.3)
        self.popularChords = approvedSongs.sorted { $0.popularityScore > $1.popularityScore }.prefix(10).map { $0 }
        
        // Yeni Gelenler (Son 3 ay)
        let threeMonthsAgo = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
        self.newArrivals = approvedSongs.filter { ($0.createdAt ?? Date(timeIntervalSince1970: 0)) > threeMonthsAgo }
            .sorted { ($0.createdAt ?? Date()) > ($1.createdAt ?? Date()) }
        
        // Onay bekleyenleri de güncelle
        self.fetchPendingSongs()
        
        // Son Çalınanlar (UserDefaults'tan yükle)
        loadRecentlyPlayed()
    }

    
    func addToRecentlyPlayed(_ song: Song) {
        var ids = UserDefaults.standard.stringArray(forKey: recentPlayedKey) ?? []
        let songId = song.id
        
        ids.removeAll { $0 == songId }
        ids.insert(songId, at: 0)
        
        // Sadece son 10 taneyi tut
        if ids.count > 10 {
            ids = Array(ids.prefix(10))
        }
        
        UserDefaults.standard.set(ids, forKey: recentPlayedKey)
        loadRecentlyPlayed()
    }
    
    private func loadRecentlyPlayed() {
        let ids = UserDefaults.standard.stringArray(forKey: recentPlayedKey) ?? []
        self.recentlyPlayed = ids.compactMap { id in
            allSongs.first { $0.id == id }
        }
    }
    
    func songsForArtist(_ artist: String) -> [Song] {
        allSongs.filter { $0.artist == artist }.sorted { $0.songName < $1.songName }
    }
    
    func filterSongs(query: String) async {
        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedQuery.isEmpty else {
            self.songs = []
            return
        }
        
        let normalizedQuery = cleanedQuery.turkeyNormalized
        let queryWords = normalizedQuery.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        
        // Capture data for background thread to avoid actor isolation issues
        let songsToFilter = self.allSongs
        
        // Veriyi arka planda işle
        let filtered = await Task.detached(priority: .userInitiated) { [normalizedQuery, queryWords] in
            // status nil olan eski şarkıları da dahil ediyoruz
            let approvedSongs = songsToFilter.filter { $0.status == "approved" || $0.status == nil }
            
            return approvedSongs.filter { song in
                let normalizedArtist = song.artist.turkeyNormalized
                let normalizedSongName = song.songName.turkeyNormalized
                
                return queryWords.allSatisfy { word in
                    normalizedArtist.contains(word) || normalizedSongName.contains(word)
                }
            }.sorted { s1, s2 in
                let n1A = s1.artist.turkeyNormalized
                let n1S = s1.songName.turkeyNormalized
                let n2A = s2.artist.turkeyNormalized
                let n2S = s2.songName.turkeyNormalized
                
                let s1Starts = n1S.hasPrefix(normalizedQuery) || n1A.hasPrefix(normalizedQuery)
                let s2Starts = n2S.hasPrefix(normalizedQuery) || n2A.hasPrefix(normalizedQuery)
                
                if s1Starts && !s2Starts { return true }
                if !s1Starts && s2Starts { return false }
                
                return n1S < n2S
            }
        }.value
        
        self.songs = filtered
    }
    
    func incrementViewCount(for song: Song) {
        let songId = song.id
        let isUserSong = songId.hasPrefix("u") || songId.hasPrefix("tmp_")
        let collection = isUserSong ? collectionUserChords : collectionChords

        // Update local state immediately
        if let index = allSongs.firstIndex(where: { $0.id == songId }) {
            allSongs[index].totalViews  = (allSongs[index].totalViews  ?? 0) + 1
            allSongs[index].recentViews = (allSongs[index].recentViews ?? 0) + 1
            // Only persist cache for user songs; bundle songs are always re-loaded from bundle
            if isUserSong {
                SyncManager.shared.saveSongsToCache(allUserSongs)
            }
        }

        // Queue the Firestore write — will be flushed next daily sync

        // NOTE: FieldValue.increment cannot be serialised, so we compute the new counts
        // from the local cache and write absolute values.
        let totalViews  = allSongs.first(where: { $0.id == songId })?.totalViews  ?? 1
        let recentViews = allSongs.first(where: { $0.id == songId })?.recentViews ?? 1
        let write = PendingWrite(
            collection: collection,
            documentId: songId,
            operation: .update,
            fields: [
                "totalViews":  .int(totalViews),
                "recentViews": .int(recentViews)
            ]
        )
        SyncManager.shared.enqueuePendingWrite(write)
    }

    // MARK: - Repertoire Management
    
    private func fetchRepertoiresFromFirestore(userId: String) {
        // Clear old listeners if any (in a real app you might want to store ListenerRegistration)
        
        // 1. Private Repertoires
        db.collection("users").document(userId).collection("repertoires").addSnapshotListener { [weak self] snapshot, _ in
            self?.combineAndSyncRepertoires()
        }
        
        // 2. Public Repertoires owned by me
        db.collection(collectionPublicRepertoires).whereField("ownerId", isEqualTo: userId).addSnapshotListener { [weak self] snapshot, _ in
            self?.combineAndSyncRepertoires()
        }
    }

    private func combineAndSyncRepertoires() {
        guard let uid = userId else { return }
        
        Task { @MainActor in
            do {
                async let privateSnapshot = db.collection("users").document(uid).collection("repertoires").getDocuments()
                async let publicSnapshot = db.collection(collectionPublicRepertoires).whereField("ownerId", isEqualTo: uid).getDocuments()
                
                let (pSnapshot, pubSnapshot) = try await (privateSnapshot, publicSnapshot)
                
                let privateReps = pSnapshot.documents.compactMap { try? $0.data(as: Repertoire.self) }
                let publicReps = pubSnapshot.documents.compactMap { try? $0.data(as: Repertoire.self) }
                
                self.repertoires = (privateReps + publicReps).sorted { ($0.createdAt ) > ($1.createdAt ) }
            } catch {
                print("Error combining repertoires: \(error)")
            }
        }
    }

    private func loadRepertoires() {
        if let data = UserDefaults.standard.data(forKey: repertoiresKey),
           let saved = try? JSONDecoder().decode([Repertoire].self, from: data) {
            self.repertoires = saved
        }
    }
    
    private func saveRepertoires() {
        if userId == nil {
            if let data = try? JSONEncoder().encode(repertoires) {
                UserDefaults.standard.set(data, forKey: repertoiresKey)
            }
        }
    }

    @Published var editorRepertoires: [Repertoire] = [] // Editörün seçtiği repertuarlar (Admins)

    func fetchPublicRepertoires() {
        db.collection(collectionPublicRepertoires)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self, let docs = snapshot?.documents else { return }
                Task { @MainActor in
                    let repertoires = docs.compactMap { try? $0.data(as: Repertoire.self) }
                        .sorted { ($0.createdAt ) > ($1.createdAt ) }
                    self.publicRepertoires = repertoires
                    self.fetchEditorRepertoires(from: repertoires)
                }
            }
    }

    private func fetchEditorRepertoires(from allPublic: [Repertoire]) {
        Task { @MainActor in
            do {
                let snapshot = try await db.collection("users").whereField("isAdmin", isEqualTo: true).getDocuments()
                let adminIds = snapshot.documents.map { $0.documentID }
                self.editorRepertoires = allPublic.filter { adminIds.contains($0.ownerId) }
            } catch {
                print("Error fetching admins: \(error)")
            }
        }
    }

    func addRepertoire(name: String) {
        let newRepertoire = Repertoire(
            id: UUID().uuidString,
            name: name,
            songIds: [],
            ownerId: userId ?? "local",
            createdAt: Date()
        )
        
        if let uid = userId {
            do {
                let docRef = db.collection("users").document(uid).collection("repertoires").document(newRepertoire.id ?? UUID().uuidString)
                try docRef.setData(from: newRepertoire)
            } catch {
                print("Error adding repertoire to Firestore: \(error)")
            }
        } else {
            repertoires.append(newRepertoire)
            saveRepertoires()
        }
    }
    
    func deleteRepertoire(at offsets: IndexSet) {
        if userId != nil {
            offsets.forEach { index in
                let repertoire = repertoires[index]
                deleteRepertoire(repertoire)
            }
        } else {
            repertoires.remove(atOffsets: offsets)
            saveRepertoires()
        }
    }

    func deleteRepertoire(_ repertoire: Repertoire) {
        if let uid = userId, let id = repertoire.id {
            if repertoire.isPublic ?? false {
                db.collection(collectionPublicRepertoires).document(id).delete()
            } else {
                db.collection("users").document(uid).collection("repertoires").document(id).delete()
            }
        } else {
            if let index = repertoires.firstIndex(where: { $0.id == repertoire.id }) {
                repertoires.remove(at: index)
                saveRepertoires()
            }
        }
    }

    func renameRepertoire(_ repertoire: Repertoire, newName: String) {
        guard repertoire.ownerId == (userId ?? "local") else { return }
        if let uid = userId, let repId = repertoire.id {
            let collection = (repertoire.isPublic ?? false) ? collectionPublicRepertoires : "users/\(uid)/repertoires"
            db.collection(collection).document(repId).updateData([
                "name": newName
            ])
        } else {
            guard let index = repertoires.firstIndex(where: { $0.id == repertoire.id }) else { return }
            repertoires[index].name = newName
            saveRepertoires()
        }
    }

    func songs(for repertoire: Repertoire) -> [Song] {
        return repertoire.songIds.compactMap { id in
            allSongs.first { $0.id == id }
        }
    }

    func addSong(_ song: Song, to repertoire: Repertoire) {
        let songId = song.id
        
        if let uid = userId, let repId = repertoire.id {
            var updatedSongIds = repertoire.songIds
            if !updatedSongIds.contains(songId) {
                updatedSongIds.append(songId)
                let collection = (repertoire.isPublic ?? false) ? collectionPublicRepertoires : "users/\(uid)/repertoires"
                db.collection(collection).document(repId).updateData([
                    "songIds": updatedSongIds
                ])
            }
        } else {
            guard let index = repertoires.firstIndex(where: { $0.id == repertoire.id }) else { return }
            if !repertoires[index].songIds.contains(songId) {
                repertoires[index].songIds.append(songId)
                saveRepertoires()
            }
        }
    }

    func removeSong(_ song: Song, from repertoire: Repertoire) {
        guard repertoire.ownerId == (userId ?? "local") else { return }
        let songId = song.id
        
        if let uid = userId, let repId = repertoire.id {
            var updatedSongIds = repertoire.songIds
            updatedSongIds.removeAll { $0 == songId }
            let collection = (repertoire.isPublic ?? false) ? collectionPublicRepertoires : "users/\(uid)/repertoires"
            db.collection(collection).document(repId).updateData([
                "songIds": updatedSongIds
            ])
        } else {
            guard let index = repertoires.firstIndex(where: { $0.id == repertoire.id }) else { return }
            repertoires[index].songIds.removeAll { $0 == songId }
            saveRepertoires()
        }
    }

    func setRepertoirePublic(_ repertoire: Repertoire, isPublic: Bool) {
        guard let uid = userId, let repId = repertoire.id else { return }
        guard repertoire.ownerId == uid else { return }
        
        let oldCollection = (repertoire.isPublic ?? false) ? collectionPublicRepertoires : "users/\(uid)/repertoires"
        let newCollection = isPublic ? collectionPublicRepertoires : "users/\(uid)/repertoires"
        
        if oldCollection == newCollection { return }
        
        var updatedRepertoire = repertoire
        updatedRepertoire.isPublic = isPublic
        
        // 1. New collection'a yaz
        do {
            try db.collection(newCollection).document(repId).setData(from: updatedRepertoire)
            // 2. Old collection'dan sil
            db.collection(oldCollection).document(repId).delete()
        } catch {
            print("Error toggling repertoire visibility: \(error)")
        }
    }

    func duplicateRepertoire(_ repertoire: Repertoire) {
        // Kopyalama her zaman kullanıcının private alanına yapılır (isPublic: false)
        let newId = UUID().uuidString
        let copy = Repertoire(
            id: newId,
            name: repertoire.name,
            songIds: repertoire.songIds,
            ownerId: userId ?? "local",
            createdAt: Date(),
            isPublic: false,
            sourceId: repertoire.id
        )
        
        if let uid = userId {
            do {
                try db.collection("users").document(uid).collection("repertoires").document(newId).setData(from: copy)
                // Local state Snapshot listener ile güncellenecektir
            } catch {
                print("Error duplicating repertoire: \(error)")
            }
        } else {
            repertoires.append(copy)
            saveRepertoires()
        }
    }

    func isRepertoireCopied(_ repertoire: Repertoire) -> Bool {
        let targetId = repertoire.id ?? ""
        return repertoires.contains { $0.sourceId == targetId }
    }

    // MARK: - User Songs Management

    func userSongs(userId: String) -> [Song] {
        return allSongs.filter { $0.ownerId == userId }
    }

    func saveSong(_ song: Song) {
        // Eğer docId boşsa veya yeni bir şarkıysa Transaction ile uX ID'si alacağız
        if song.docId.isEmpty {
            saveNewUserSong(song)
        } else {
            // Varolan şarkıyı güncelle
            updateExistingSong(song)
        }
    }
    
    private func saveNewUserSong(_ song: Song) {
        // Generate a temporary local ID using timestamp to avoid collisions.
        // The real uX ID is assigned when the write is flushed to Firestore via transaction.
        // For now we store it locally with a "tmp_" prefix and queue the actual
        // Firestore transaction as a set operation.
        let tmpId = "tmp_\(Int(Date().timeIntervalSince1970))"
        var newSong = song
        newSong.docId = tmpId

        // 1. Save locally immediately
        allSongs.append(newSong)
        SyncManager.shared.saveSongsToCache(allUserSongs)
        processDashboardData()
        print("✅ saveNewUserSong: Saved locally with tmpId=\(tmpId)")

        // 2. Immediately write to Firestore to get real uX ID (this is one write only)
        Task { @MainActor in
            let counterRef = db.collection(metadataCollection).document(countersDocument)
            let userChordsRef = db.collection(collectionUserChords)

            db.runTransaction({ (transaction, errorPointer) -> Any? in
                let counterSnapshot: DocumentSnapshot
                do {
                    try counterSnapshot = transaction.getDocument(counterRef)
                } catch let fetchError as NSError {
                    errorPointer?.pointee = fetchError
                    return nil
                }

                var currentCount = counterSnapshot.exists
                    ? (counterSnapshot.data()?["userSongCount"] as? Int ?? 0)
                    : 0
                currentCount += 1
                let newDocId = "u\(currentCount)"
                var finalSong = song
                finalSong.docId = newDocId

                if counterSnapshot.exists {
                    transaction.updateData(["userSongCount": currentCount], forDocument: counterRef)
                } else {
                    transaction.setData(["userSongCount": currentCount], forDocument: counterRef)
                }
                do {
                    try transaction.setData(from: finalSong, forDocument: userChordsRef.document(newDocId))
                } catch let encodeError as NSError {
                    errorPointer?.pointee = encodeError
                    return nil
                }
                return finalSong
            }) { [weak self] (result, error) in
                guard let self = self else { return }
                Task { @MainActor in
                    if let error = error {
                        print("❌ saveNewUserSong transaction failed: \(error.localizedDescription)")
                    } else if let finalSong = result as? Song {
                        // Replace tmp entry with the real one
                        self.allSongs.removeAll { $0.docId == tmpId }
                        self.allSongs.append(finalSong)
                        SyncManager.shared.saveSongsToCache(self.allUserSongs)
                        self.processDashboardData()
                        print("✅ saveNewUserSong: Firestore ID assigned: \(finalSong.docId)")

                    }
                }
            }
        }
    }
    
    private func updateExistingSong(_ song: Song) {
        // 1. Update local state immediately
        if let index = allSongs.firstIndex(where: { $0.docId == song.docId }) {
            allSongs[index] = song
            processDashboardData()
        }

        // Only user-chords (u* prefix) are written to Firestore.
        // Bundle songs (numeric docIds) are read-only from the app bundle.
        guard song.docId.hasPrefix("u") || song.docId.hasPrefix("tmp_") else {
            print("ℹ️ updateExistingSong: Bundle song \(song.docId) — local update only, no Firestore write.")
            return
        }

        // 2. Persist user-chords cache
        SyncManager.shared.saveSongsToCache(allUserSongs)

        // 3. Queue Firestore write for daily flush
        guard let fields = encodeSongToCodableFields(song) else {
            print("⚠️ updateExistingSong: Failed to encode song fields.")
            return
        }
        let write = PendingWrite(
            collection: collectionUserChords,
            documentId: song.docId,
            operation: .set,
            fields: fields
        )
        SyncManager.shared.enqueuePendingWrite(write)
    }

    /// Encodes a Song to a [String: CodableValue] dict for use in PendingWrite.
    private func encodeSongToCodableFields(_ song: Song) -> [String: CodableValue]? {
        guard let data = try? JSONEncoder().encode(song),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var fields: [String: CodableValue] = [:]
        for (key, value) in dict {
            switch value {
            case let v as String:  fields[key] = .string(v)
            case let v as Int:     fields[key] = .int(v)
            case let v as Double:  fields[key] = .double(v)
            case let v as Bool:    fields[key] = .bool(v)
            default:               break
            }
        }
        return fields
    }

    func deleteSong(_ song: Song) {
        let songId = song.id

        // 1. Remove from local state immediately
        allSongs.removeAll { $0.docId == songId || $0.id == songId }
        processDashboardData()

        // Only user-chords can be deleted from Firestore.
        // Bundle songs cannot be deleted (they are read-only from the app bundle).
        guard songId.hasPrefix("u") || songId.hasPrefix("tmp_") else {
            print("ℹ️ deleteSong: Bundle song \(songId) — local removal only, no Firestore write.")
            return
        }

        // 2. Persist user-chords cache
        SyncManager.shared.saveSongsToCache(allUserSongs)

        // 3. Queue Firestore delete for daily flush
        let write = PendingWrite(
            collection: collectionUserChords,
            documentId: songId,
            operation: .delete
        )
        SyncManager.shared.enqueuePendingWrite(write)
    }
    
    func approveSong(_ song: Song) {
        let songId = song.id
        let collection = songId.hasPrefix("u") ? collectionUserChords : collectionChords

        // Update local cache
        if let index = allSongs.firstIndex(where: { $0.id == songId }) {
            allSongs[index].status = "approved"
            SyncManager.shared.saveSongsToCache(allSongs)
            processDashboardData()
        }
        // Queue write — admin approval must reach Firestore promptly, so flush immediately
        Task {
            do {
                try await db.collection(collection).document(songId).updateData(["status": "approved"])
            } catch {
                // On failure, queue for later
                let write = PendingWrite(collection: collection, documentId: songId,
                                         operation: .update, fields: ["status": .string("approved")])
                SyncManager.shared.enqueuePendingWrite(write)
                print("⚠️ approveSong: Direct write failed, queued. \(error)")
            }
        }
    }

    func rejectSong(_ song: Song) {
        let songId = song.id
        let collection = songId.hasPrefix("u") ? collectionUserChords : collectionChords

        // Update local cache
        if let index = allSongs.firstIndex(where: { $0.id == songId }) {
            allSongs[index].status = "rejected"
            SyncManager.shared.saveSongsToCache(allSongs)
            processDashboardData()
        }
        Task {
            do {
                try await db.collection(collection).document(songId).updateData(["status": "rejected"])
            } catch {
                let write = PendingWrite(collection: collection, documentId: songId,
                                         operation: .update, fields: ["status": .string("rejected")])
                SyncManager.shared.enqueuePendingWrite(write)
                print("⚠️ rejectSong: Direct write failed, queued. \(error)")
            }
        }
    }
    
    // MARK: - User Song Preferences
    
    private func getPrefKey(for songId: String) -> String {
        if let uid = userId {
            return "pref_\(uid)_\(songId)"
        }
        return "pref_guest_\(songId)"
    }
    
    func fetchSongPreference(for songId: String) {
        let prefKey = getPrefKey(for: songId)
        // Load locally first
        if let data = UserDefaults.standard.data(forKey: prefKey),
           let pref = try? JSONDecoder().decode(UserSongPreference.self, from: data) {
            self.songPreferences[songId] = pref
        }
        
        // Fetch from Firebase
        guard let uid = userId else { return }
        
        Task {
            do {
                let snapshot = try await db.collection("users").document(uid).collection("preferences").document(songId).getDocument()
                if let data = try? snapshot.data(as: UserSongPreference.self) {
                    self.songPreferences[songId] = data
                    // Update local cache
                    let currentPrefKey = self.getPrefKey(for: songId)
                    if let encoded = try? JSONEncoder().encode(data) {
                        UserDefaults.standard.set(encoded, forKey: currentPrefKey)
                    }
                }
            } catch {
                print("Error fetching preference: \(error)")
            }
        }
    }

    func saveSongPreference(songId: String, key: String, capo: Int, note: String) {
        let pref = UserSongPreference(songId: songId, selectedKeyRoot: key, capoFret: capo, note: note)
        self.songPreferences[songId] = pref
        
        // Save locally
        let prefKey = getPrefKey(for: songId)
        if let encoded = try? JSONEncoder().encode(pref) {
            UserDefaults.standard.set(encoded, forKey: prefKey)
        }
        
        // Save to Firebase
        if let uid = userId {
            do {
                try db.collection("users").document(uid).collection("preferences").document(songId).setData(from: pref)
            } catch {
                print("Error saving preference: \(error)")
            }
        }
    }
    
    func deleteSongPreference(songId: String) {
        self.songPreferences.removeValue(forKey: songId)
        let prefKey = getPrefKey(for: songId)
        UserDefaults.standard.removeObject(forKey: prefKey)
        
        if let uid = userId {
            db.collection("users").document(uid).collection("preferences").document(songId).delete()
        }
    }
}


extension String {
    nonisolated var turkeyNormalized: String {
        let replacements: [String: String] = [
            "ç": "c", "Ç": "c",
            "ğ": "g", "Ğ": "g",
            "ı": "i", "I": "i", "İ": "i",
            "ö": "o", "Ö": "o",
            "ş": "s", "Ş": "s",
            "ü": "u", "Ü": "u"
        ]
        var result = self.lowercased(with: Locale(identifier: "tr-TR"))
        for (key, value) in replacements {
            result = result.replacingOccurrences(of: key, with: value)
        }
        return result.folding(options: .diacriticInsensitive, locale: Locale(identifier: "tr-TR"))
    }
}

struct UserSongPreference: Codable, Equatable, Sendable {
    var songId: String
    var selectedKeyRoot: String
    var capoFret: Int
    var note: String
}

