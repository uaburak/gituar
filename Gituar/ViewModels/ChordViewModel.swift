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
    @Published var allSongs: [Song] = [] { // Tüm şarkılar (Cache)
        didSet { updateVisibleSongs() }
    }
    @Published var publicRepertoires: [Repertoire] = [] // Paylaşılan repertuarlar
    @Published var songPreferences: [String: UserSongPreference] = [:] // Kullanıcıya özel şarkı ayarları
    @Published var pendingSongs: [Song] = [] // Onay bekleyen şarkılar
    /// Sanatçı → şarkı sayısı sözlüğü — AllArtistsView'da List satırlarını hızlandırır.
    @Published var artistSongCount: [String: Int] = [:]
    
    @Published var blockedUserIDs: [String] = [] {
        didSet {
            UserDefaults.standard.set(blockedUserIDs, forKey: "blockedUserIDs")
            updateVisibleSongs()
            if !searchText.isEmpty {
                Task {
                    await filterSongs(query: searchText)
                }
            }
        }
    }
    
    private let collectionChords = "chords"
    private let collectionUserChords = "user-chords"
    private let collectionPublicRepertoires = "public-repertoires"
    private let collectionSongMetrics = "song-metrics"
    private let metadataCollection = "metadata"
    private let countersDocument = "counters"

    private var db = Firestore.firestore()
    private var cancellables = Set<AnyCancellable>()
    private var authListener: AuthStateDidChangeListenerHandle?
    private var adminIdsCache: [String]? = nil
    /// Aktif Firestore snapshot listener'larını tutar — auth değişiminde remove() ile temizlenir.
    private var repertoireListeners: [ListenerRegistration] = []

    private let recentPlayedKey = "recentlyPlayedIds"
    private let repertoiresKey  = "user_repertoires"

    var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }
    // NOT: `userId` kaldırıldı — currentUserId kullanılıyor.

    /// Only the songs added by users (docId starts with "u" or "tmp_").
    /// Bundle/system songs are excluded — they don't need to be cached or synced.
    private var allUserSongs: [Song] {
        allSongs.filter { $0.docId.hasPrefix("u") || $0.docId.hasPrefix("tmp_") }
    }

    /// User-chords'un ayrı, kararlı kopyası.
    /// Storage subscription'ı allSongs'u overwrite ettiğinde user-chords'un kaybolmaması için.
    private var cachedUserChords: [Song] = []

    /// Engelleme + onay filtresi uygulanmış, UI için güvenli şarkı listesi.
    /// `allSongs` veya `blockedUserIDs` değiştiğinde `updateVisibleSongs()` ile yenilenir.
    /// Computed property yerine cached stored property — her UI render'da yeniden hesaplanmaz.
    @Published private(set) var visibleSongs: [Song] = []

    /// visibleSongs'u günceller. allSongs veya blockedUserIDs her değiştiğinde çağrılır.
    private func updateVisibleSongs() {
        let songs = allSongs
        let blocked = blockedUserIDs
        Task.detached(priority: .userInitiated) {
            let filtered = songs.filter {
                ($0.status == "approved" || $0.status == nil) &&
                !(($0.ownerId.map { !$0.isEmpty } ?? false) && blocked.contains($0.ownerId!))
            }
            await MainActor.run { [weak self] in
                self?.visibleSongs = filtered
                self?.processDashboardData()
            }
        }
    }

    
    init() {
        self.blockedUserIDs = UserDefaults.standard.stringArray(forKey: "blockedUserIDs") ?? []
        setupAuthListener()
        fetchAllSongs()   // Sadece user-chords yükler

        // ChordsStorageManager (Firebase Storage) hazır olduğunda resmi şarkıları merge et.
        // Bu subscription sayesinde Storage arka planda indirmeyi bitirince allSongs
        // otomatik güncellenir; kullanıcı hiçbir yerde bekletilmez.
        ChordsStorageManager.shared.$songs
            .dropFirst()            // .idle başlangıç değerini atla
            .receive(on: RunLoop.main)
            .sink { [weak self] storageSongs in
                guard let self, !storageSongs.isEmpty else { return }
                let officialSongs = storageSongs.map { $0.toSong() }
                // cachedUserChords kullan — allSongs’u yeniden filtreleme (race condition)
                self.allSongs = officialSongs + self.cachedUserChords
                // allSongs.didSet → updateVisibleSongs() → processDashboardData() otomatik tetikler
                self.fetchPopularityRegistry()
                print("✅ ChordViewModel: \(officialSongs.count) resmi şarkı Storage'dan merge edildi, \(self.cachedUserChords.count) user-chord korundu.")
            }
            .store(in: &cancellables)

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
                if let self = self, !self.publicRepertoires.isEmpty {
                    self.fetchEditorRepertoires(from: self.publicRepertoires)
                }
            }
        }
    }
    
    private func loadUserData(userId: String?) {
        songPreferences.removeAll()
        if let uid = currentUserId {
            fetchRepertoiresFromFirestore(userId: uid)
            loadBlockedUsersFromFirestore(userId: uid)
        } else {
            // Guest mode veya çıkış — listener'ları temizle
            repertoireListeners.forEach { $0.remove() }
            repertoireListeners.removeAll()
            loadRepertoires()
        }
    }

    // MARK: - User-Chords Loading
    //
    // Resmi şarkılar artık ChordsStorageManager (Firebase Storage) üzerinden gelir.
    // Bu fonksiyon SADECE kullanıcıların eklediği şarkıları (user-chords) yükler.
    // İki kaynak init() içindeki Combine subscription'ı ile allSongs'ta birleştirilir.

    private func fetchAllSongs() {
        guard !isLoading else { return }
        isLoading = true

        Task { @MainActor in
            let syncManager = SyncManager.shared

            // 1. Diskten cache'lenmiş user-chords'u hızlıca yükle (anlık gösterim için)
            let cachedUserSongs = syncManager.loadSongsFromCache() ?? []
            print("📦 ChordViewModel: \(cachedUserSongs.count) user songs loaded from cache.")

            // cachedUserChords'u güncelle — Storage subscription race condition'ını engeller
            self.cachedUserChords = cachedUserSongs

            // Resmi şarkılar Storage'dan henüz gelmediyse sadece cache'i göster
            let storageSongs = ChordsStorageManager.shared.songs.map { $0.toSong() }
            self.allSongs = storageSongs + cachedUserSongs
            // allSongs.didSet → updateVisibleSongs() → processDashboardData() otomatik tetikler
            self.isLoading = false
            self.loadUserData(userId: self.currentUserId)
            self.fetchPopularityRegistry()

            // 2. HER AÇILIŞTA Firestore'dan user-chords çek — cache sadece hızlı gösterim için
            // Bu, kullanıcıların şarkılarının her zaman görünmesini garantiler.
            print("🔄 ChordViewModel: Fetching user-chords from Firestore…")
            do {
                let freshUserSongs = try await syncManager.performFullSync(
                    collectionChords: collectionChords,
                    collectionUserChords: collectionUserChords
                )
                // cachedUserChords'u Firestore'dan gelen taze verilerle güncelle
                self.cachedUserChords = freshUserSongs
                // Resmi şarkıları Storage'dan al (hazırsa), user-chords'u tazele
                let latestStorage = ChordsStorageManager.shared.songs.map { $0.toSong() }
                self.allSongs = latestStorage + freshUserSongs
                // allSongs.didSet → updateVisibleSongs() → processDashboardData() otomatik tetikler
                self.loadUserData(userId: self.currentUserId)
                self.fetchPopularityRegistry()
                print("✅ ChordViewModel: \(freshUserSongs.count) user-chord(s) loaded from Firestore.")
            } catch {
                print("❌ ChordViewModel: Firestore user-chords fetch failed: \(error)")
                // Hata durumunda cache'den yükleme zaten yapıldı, devam edilebilir
            }

            // 3. Bekleyen yazmaları Firestore'a flush et
            if syncManager.hasPendingWrites {
                await syncManager.flushPendingWrites()
            }
        }
    }

    /// Kullanıcı şarkılarını (user-chords) Firestore'dan zorla yeniler (ör. pull-to-refresh).
    /// Resmi şarkılar ChordsStorageManager'dan otomatik gelir, burada yenileme gerekmez.
    func forceSync() {
        guard !isLoading else { return }
        isLoading = true
        Task { @MainActor in
            let syncManager = SyncManager.shared
            do {
                let freshUserSongs = try await syncManager.performFullSync(
                    collectionChords: collectionChords,
                    collectionUserChords: collectionUserChords
                )
                // cachedUserChords'u güncelle
                self.cachedUserChords = freshUserSongs
                // Resmi şarkıları Storage'dan al, user-chords'u tazele
                let storageSongs = ChordsStorageManager.shared.songs.map { $0.toSong() }
                self.allSongs = storageSongs + freshUserSongs
                // allSongs.didSet → updateVisibleSongs() → processDashboardData() otomatik tetikler
                self.loadUserData(userId: self.currentUserId)
                self.fetchPopularityRegistry()
            } catch {
                print("❌ ChordViewModel: forceSync failed: \(error)")
            }
            self.isLoading = false
        }
    }

    
    /// Onay bekleyen şarkıları Firestore'dan çeker.
    /// Sadece admin kullanıcılar için çağrılmalı.
    func fetchPendingSongs() {
        Task {
            do {
                let snapshot = try await db.collection(collectionUserChords)
                    .whereField("status", isEqualTo: "pending")
                    .getDocuments()
                let songs = snapshot.documents.compactMap { doc -> Song? in
                    if var song = try? doc.data(as: Song.self) {
                        if song.docId.isEmpty { song.docId = doc.documentID }
                        return song
                    }
                    return nil
                }
                await MainActor.run {
                    self.pendingSongs = songs
                }
            } catch {
                print("❌ fetchPendingSongs: \(error.localizedDescription)")
                // Fallback: client-side filtre
                await MainActor.run {
                    self.pendingSongs = self.allSongs.filter { $0.status == "pending" }
                }
            }
        }
    }
    
    private func fetchPopularityRegistry() {
        Task {
            do {
                let snapshot = try await db.collection(metadataCollection).document("popularity_registry").getDocument(source: .server)
                guard let data = snapshot.data(), let metrics = data["metrics"] as? [String: [Int]] else { return }
                
                await MainActor.run {
                    var didUpdate = false
                    for (songId, values) in metrics {
                        if values.count >= 3, let index = self.allSongs.firstIndex(where: { $0.id == songId }) {
                            // Only update if remote is greater than local to preserve recent offline increments
                            if values[0] > (self.allSongs[index].totalViews ?? 0) {
                                self.allSongs[index].totalViews = values[0]
                                didUpdate = true
                            }
                            if values[1] > (self.allSongs[index].recentViews ?? 0) {
                                self.allSongs[index].recentViews = values[1]
                                didUpdate = true
                            }
                            if values[2] > (self.allSongs[index].repertoireAdds ?? 0) {
                                self.allSongs[index].repertoireAdds = values[2]
                                didUpdate = true
                            }
                        }
                    }
                    if didUpdate {
                        self.processDashboardData()
                    }
                }
            } catch {
                print("⚠️ fetchPopularityRegistry failed or not created yet: \(error.localizedDescription)")
            }
        }
    }
    
    private func processDashboardData() {
        // visibleSongs: engelleme + onay filtresi updateVisibleSongs() ile zaten uygulandı
        let approvedSongs = visibleSongs
        let threeMonthsAgo = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()

        // Ağır sort/filter işlemlerini background'a taşı — main thread bloklanmaz
        Task.detached(priority: .utility) {
            // Sanatçıları alfabetik listele
            let artistList = Array(Set(approvedSongs.map { $0.artist })).sorted()

            // Sanatçı → şarkı sayısı dictionary (AllArtistsView için O(n) önceden hesaplama)
            var countDict: [String: Int] = [:]
            for song in approvedSongs {
                countDict[song.artist, default: 0] += 1
            }

            // En çok eklenenler (repertoireAdds'e göre)
            let mostAddedResult = approvedSongs.sorted { ($0.repertoireAdds ?? 0) > ($1.repertoireAdds ?? 0) }.prefix(10).map { $0 }

            // Popülerler (Ağırlıklı Algoritma)
            let popularResult = approvedSongs.sorted { $0.popularityScore > $1.popularityScore }.prefix(10).map { $0 }

            // Yeni Gelenler (Son 3 ay)
            let newArrivalsResult = approvedSongs
                .filter { ($0.createdAt ?? Date(timeIntervalSince1970: 0)) > threeMonthsAgo }
                .sorted { ($0.createdAt ?? Date()) > ($1.createdAt ?? Date()) }

            await MainActor.run { [weak self] in
                self?.artists = artistList
                self?.artistSongCount = countDict
                self?.mostAdded = mostAddedResult
                self?.popularChords = popularResult
                self?.newArrivals = newArrivalsResult
                self?.loadRecentlyPlayed()
            }
        }
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
        // visibleSongs zaten cache'li — bu filtre sadece artist sayfasında çağrılır, kabul edilebilir
        visibleSongs.filter { $0.artist == artist }.sorted { $0.songName < $1.songName }
    }
    
    func filterSongs(query: String) async {
        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedQuery.isEmpty else {
            self.songs = []
            return
        }
        
        let normalizedQuery = cleanedQuery.turkeyNormalized
        let queryWords = normalizedQuery.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        
        // visibleSongs yerine direkt filtrele — arama zaten approved+blocked kontrolü yapar
        let songsToFilter = self.visibleSongs
        
        // Veriyi arka planda işle — visibleSongs zaten filtreli
        let filtered = await Task.detached(priority: .userInitiated) { [normalizedQuery, queryWords] in
            return songsToFilter.filter { song in
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
        let collection = isUserSong ? collectionUserChords : collectionSongMetrics

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
            operation: .set, // Use set with merge:true (updated in SyncManager) to create if missing
            fields: [
                "totalViews":  .int(totalViews),
                "recentViews": .int(recentViews)
            ]
        )
        SyncManager.shared.enqueuePendingWrite(write)
    }

    // MARK: - Repertoire Management
    
    private func fetchRepertoiresFromFirestore(userId: String) {
        // Mevcut listener'ları temizle (auth değişimi veya yeniden çağrı durumunda)
        repertoireListeners.forEach { $0.remove() }
        repertoireListeners.removeAll()

        // Private state — snapshot listener verilerini geçici tutar
        var privateReps: [Repertoire] = []
        var myPublicReps: [Repertoire] = []

        func merged() -> [Repertoire] {
            (privateReps + myPublicReps).sorted { $0.createdAt > $1.createdAt }
        }

        // 1. Private Repertoires — snapshot verilerini direkt kullan
        let l1 = db.collection("users").document(userId).collection("repertoires")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, let snapshot, error == nil else { return }
                privateReps = snapshot.documents.compactMap { try? $0.data(as: Repertoire.self) }
                self.repertoires = merged()
            }
        repertoireListeners.append(l1)

        // 2. Public Repertoires sahipliğinde — snapshot verilerini direkt kullan
        let l2 = db.collection(collectionPublicRepertoires)
            .whereField("ownerId", isEqualTo: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, let snapshot, error == nil else { return }
                myPublicReps = snapshot.documents.compactMap { try? $0.data(as: Repertoire.self) }
                self.repertoires = merged()
            }
        repertoireListeners.append(l2)
    }

    private func loadRepertoires() {
        if let data = UserDefaults.standard.data(forKey: repertoiresKey),
           let saved = try? JSONDecoder().decode([Repertoire].self, from: data) {
            self.repertoires = saved
        }
    }
    
    private func saveRepertoires() {
        if currentUserId == nil {
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
                if let cached = adminIdsCache {
                    self.editorRepertoires = allPublic.filter { cached.contains($0.ownerId) }
                    return
                }
                
                let snapshot = try await db.collection("users").whereField("isAdmin", isEqualTo: true).getDocuments()
                let adminIds = snapshot.documents.map { $0.documentID }
                self.adminIdsCache = adminIds
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
            ownerId: currentUserId ?? "local",
            createdAt: Date(),
            isPublic: false
        )
        
        if let uid = currentUserId {
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

    // MARK: - Admin Bulk Import

    struct BulkRepertoireEntry: Codable {
        let name: String
        let songIds: [String]
    }

    /// Admin kullanıcıların JSON dosyasından toplu repertuar eklemesini sağlar.
    /// Her entry, public-repertoires collection'a isPublic: true olarak yazılır.
    /// - Returns: (başarılı, hatalı) adedi
    func bulkImportRepertoires(
        entries: [BulkRepertoireEntry],
        onProgress: @escaping (Int, Int) -> Void
    ) async throws -> (success: Int, failed: Int) {
        guard let uid = currentUserId else {
            throw BulkImportError.notAuthenticated
        }

        var successCount = 0
        var failedCount = 0
        let total = entries.count

        for (index, entry) in entries.enumerated() {
            let repId = UUID().uuidString
            let repertoire = Repertoire(
                id: repId,
                name: entry.name,
                songIds: entry.songIds,
                ownerId: uid,
                createdAt: Date().addingTimeInterval(TimeInterval(-index)), // sıra korunsun
                isPublic: true
            )

            do {
                try db.collection(collectionPublicRepertoires).document(repId).setData(from: repertoire)
                successCount += 1
            } catch {
                print("❌ bulkImportRepertoires: '\(entry.name)' yazılamadı: \(error)")
                failedCount += 1
            }

            await MainActor.run {
                onProgress(index + 1, total)
            }
        }

        return (successCount, failedCount)
    }

    enum BulkImportError: LocalizedError {
        case notAuthenticated
        case invalidJSON

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "Bu işlem için giriş yapmanız gerekiyor."
            case .invalidJSON: return "JSON dosyası geçerli bir format içermiyor."
            }
        }
    }

    /// Yeni kullanıcı için 4 sabit varsayılan repertuarı oluşturur.
    /// Bu repertuarlar isPublic: false (gizli) olarak oluşturulur.
    func createDefaultRepertoires(for userId: String) {
        let defaultNames = ["Favoriler", "Sahne", "Sahil", "Çalışılacak"]
        for (index, name) in defaultNames.enumerated() {
            let repertoire = Repertoire(
                id: UUID().uuidString,
                name: name,
                songIds: [],
                ownerId: userId,
                createdAt: Date().addingTimeInterval(TimeInterval(-index)), // sıra korunsun
                isPublic: false
            )
            do {
                let docRef = db.collection("users").document(userId).collection("repertoires").document(repertoire.id ?? UUID().uuidString)
                try docRef.setData(from: repertoire)
            } catch {
                print("Error creating default repertoire '\(name)': \(error)")
            }
        }
    }
    
    func deleteRepertoire(at offsets: IndexSet) {
        if currentUserId != nil {
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
        if let uid = currentUserId, let id = repertoire.id {
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
        guard repertoire.ownerId == (currentUserId ?? "local") else { return }
        if let uid = currentUserId, let repId = repertoire.id {
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
        
        if let uid = currentUserId, let repId = repertoire.id {
            var updatedSongIds = repertoire.songIds
            if !updatedSongIds.contains(songId) {
                updatedSongIds.append(songId)
                let collection = (repertoire.isPublic ?? false) ? collectionPublicRepertoires : "users/\(uid)/repertoires"
                db.collection(collection).document(repId).updateData([
                    "songIds": updatedSongIds
                ])
                incrementRepertoireAdds(for: song)
            }
        } else {
            guard let index = repertoires.firstIndex(where: { $0.id == repertoire.id }) else { return }
            if !repertoires[index].songIds.contains(songId) {
                repertoires[index].songIds.append(songId)
                saveRepertoires()
                incrementRepertoireAdds(for: song)
            }
        }
    }
    
    private func incrementRepertoireAdds(for song: Song) {
        let songId = song.id
        let isUserSong = songId.hasPrefix("u") || songId.hasPrefix("tmp_")
        let collection = isUserSong ? collectionUserChords : collectionSongMetrics

        if let index = allSongs.firstIndex(where: { $0.id == songId }) {
            allSongs[index].repertoireAdds = (allSongs[index].repertoireAdds ?? 0) + 1
            if isUserSong {
                SyncManager.shared.saveSongsToCache(allUserSongs)
            }
        }

        let repAdds = allSongs.first(where: { $0.id == songId })?.repertoireAdds ?? 1
        let write = PendingWrite(
            collection: collection,
            documentId: songId,
            operation: .set, 
            fields: [
                "repertoireAdds": .int(repAdds)
            ]
        )
        SyncManager.shared.enqueuePendingWrite(write)
    }

    func removeSong(_ song: Song, from repertoire: Repertoire) {
        guard repertoire.ownerId == (currentUserId ?? "local") else { return }
        let songId = song.id
        
        if let uid = currentUserId, let repId = repertoire.id {
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
        guard let uid = currentUserId, let repId = repertoire.id else { return }
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
            ownerId: currentUserId ?? "local",
            createdAt: Date(),
            isPublic: false,
            sourceId: repertoire.id
        )
        
        if let uid = currentUserId {
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
        allSongs.filter { $0.ownerId == userId }
    }

    // MARK: - Blocking

    /// Bir kullanıcıyı engeller — hem local state hem Firestore'a yazar.
    func blockUser(ownerId: String) {
        guard !blockedUserIDs.contains(ownerId) else { return }
        blockedUserIDs.append(ownerId) // didSet → UserDefaults + UI
        guard let uid = currentUserId else { return }
        db.collection("users").document(uid).updateData([
            "blockedUsers": FieldValue.arrayUnion([ownerId])
        ]) { error in
            if let error { print("❌ blockUser Firestore: \(error.localizedDescription)") }
        }
    }

    /// Bir kullanıcının engelini kaldırır — hem local state hem Firestore'a yazar.
    func unblockUser(ownerId: String) {
        blockedUserIDs.removeAll { $0 == ownerId }
        guard let uid = currentUserId else { return }
        db.collection("users").document(uid).updateData([
            "blockedUsers": FieldValue.arrayRemove([ownerId])
        ]) { error in
            if let error { print("❌ unblockUser Firestore: \(error.localizedDescription)") }
        }
    }

    /// Oturum açıldığında Firestore'daki engelleme listesini yükler.
    private func loadBlockedUsersFromFirestore(userId: String) {
        Task {
            do {
                let doc = try await db.collection("users").document(userId).getDocument()
                if let blocked = doc.data()?["blockedUsers"] as? [String] {
                    await MainActor.run {
                        self.blockedUserIDs = blocked
                        UserDefaults.standard.set(blocked, forKey: "blockedUserIDs")
                    }
                }
            } catch {
                print("⚠️ loadBlockedUsersFromFirestore: \(error.localizedDescription)")
            }
        }
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
        cachedUserChords = allUserSongs
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
                        self.cachedUserChords = self.allUserSongs
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
        // Bundle songs are now stored in Firebase Storage.
        if songId.hasPrefix("u") || songId.hasPrefix("tmp_") {
            // 2. Persist user-chords cache
            cachedUserChords = allUserSongs
            SyncManager.shared.saveSongsToCache(allUserSongs)

            // 3. Immediately delete from Firestore (Admin / User action should reflect promptly)
            Task {
                do {
                    try await db.collection(collectionUserChords).document(songId).delete()
                    print("✅ deleteSong: User chord \(songId) deleted directly from Firestore.")
                } catch {
                    // Fallback to queue if offline
                    let write = PendingWrite(
                        collection: collectionUserChords,
                        documentId: songId,
                        operation: .delete
                    )
                    SyncManager.shared.enqueuePendingWrite(write)
                    print("⚠️ deleteSong: Direct delete failed, queued. \(error)")
                }
            }
        } else {
            // Official Song - Delete from Firebase Storage JSON
            Task {
                do {
                    try await ChordsStorageManager.shared.deleteOfficialSong(songId: songId)
                    print("✅ deleteSong: Official song \(songId) deleted from Storage.")
                } catch {
                    print("❌ deleteSong: Failed to delete official song from Storage: \(error)")
                }
            }
        }
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
        if let uid = currentUserId {
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
        guard let uid = currentUserId else { return }
        
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
        if let uid = currentUserId {
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
        
        if let uid = currentUserId {
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

