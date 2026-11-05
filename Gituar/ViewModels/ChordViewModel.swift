import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine
import SwiftUI

// MARK: - ChordViewModel (Offline-First)

@MainActor
class ChordViewModel: ObservableObject {
    @Published var isLoading: Bool = false
    
    // Dashboard Verileri
    @Published var repertoires: [Repertoire] = []
    @Published var recentlyPlayed: [Song] = []
    @Published var mostAdded: [Song] = []
    @Published var newArrivals: [Song] = []
    @Published var artists: [String] = [] // Sanatçı listesi
    @Published var allSongs: [Song] = [] { // Tüm şarkılar (Cache)
        didSet {
            songsById = Dictionary(allSongs.map { ($0.docId, $0) }, uniquingKeysWith: { first, _ in first })
            updateVisibleSongs()
        }
    }
    @Published var publicRepertoires: [Repertoire] = [] { // Paylaşılan repertuarlar
        didSet { updateMostAdded() }
    }
    @Published var songPreferences: [String: UserSongPreference] = [:] // Kullanıcıya özel şarkı ayarları
    @Published var pendingSongs: [Song] = [] // Onay bekleyen şarkılar
    /// Sanatçı → şarkı sayısı sözlüğü — AllArtistsView'da List satırlarını hızlandırır.
    @Published var artistSongCount: [String: Int] = [:]
    
    @Published var blockedUserIDs: [String] = [] {
        didSet {
            UserDefaults.standard.set(blockedUserIDs, forKey: "blockedUserIDs")
            updateVisibleSongs()
        }
    }

    /// `gituar://song/<docId>` bağlantısıyla açılan şarkı — HomeView bu değere göre şarkıyı push eder.
    @Published var deepLinkedSong: Song?
    
    private let collectionChords = "chords"
    private let collectionUserChords = "user-chords"
    private let collectionPublicRepertoires = "public-repertoires"
    private let metadataCollection = "metadata"
    private let countersDocument = "counters"

    private var db = Firestore.firestore()
    private var cancellables = Set<AnyCancellable>()
    private var authListener: AuthStateDidChangeListenerHandle?
    private var adminIdsCache: [String]? = nil
    /// Aktif Firestore snapshot listener'larını tutar — auth değişiminde remove() ile temizlenir.
    private var repertoireListeners: [ListenerRegistration] = []
    /// Public repertuar dinleyicisi. Hata alırsa Firestore dinleyiciyi kapatır; nil'e çekilip auth değişiminde yeniden kurulur.
    private var publicRepertoiresListener: ListenerRegistration?
    /// Yüklemesi (uX ID ataması) süren tmp_ şarkılar — aynı şarkının iki kez yüklenmesini engeller.
    private var uploadingTmpIds: Set<String> = []
    /// Yüklemesi sürerken kullanıcının sildiği tmp_ şarkılar — yükleme bitince sunucudaki kopya da silinir.
    private var tmpIdsDeletedWhileUploading: Set<String> = []
    private var isSyncingUserChords = false
    /// Sync sürerken yüklemesi tamamlanan şarkılar — sync sonucu bunları henüz içermiyor olabilir.
    private var uploadedDuringSync: [Song] = []
    private var pendingDeepLinkSongId: String?

    private let recentPlayedKey = "recentlyPlayedIds"
    private let repertoiresKey  = "user_repertoires"

    var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }
    // NOT: `userId` kaldırıldı — currentUserId kullanılıyor.

    /// Only the songs added by users (docId starts with "u" or "tmp_").
    /// Bundle/system songs are excluded — they don't need to be cached or synced.
    private var allUserSongs: [Song] {
        allSongs.filter { Self.isUserChord($0.docId) }
    }

    private static func isUserChord(_ docId: String) -> Bool {
        docId.hasPrefix("u") || docId.hasPrefix("tmp_")
    }

    /// User-chords'un ayrı, kararlı kopyası.
    /// Storage subscription'ı allSongs'u overwrite ettiğinde user-chords'un kaybolmaması için.
    private var cachedUserChords: [Song] = []

    /// docId → şarkı sözlüğü. Repertuar ve "son çalınanlar" gibi ID listelerini
    /// her seferinde tüm şarkıları taramadan çözmek için allSongs ile birlikte yenilenir.
    private var songsById: [String: Song] = [:]

    /// Engelleme + onay filtresi uygulanmış, UI için güvenli şarkı listesi.
    /// `allSongs` veya `blockedUserIDs` değiştiğinde `updateVisibleSongs()` ile yenilenir.
    /// Computed property yerine cached stored property — her UI render'da yeniden hesaplanmaz.
    @Published private(set) var visibleSongs: [Song] = []
    /// visibleSongs her yenilendiğinde artar — view'lar aramayı yeniden çalıştırmak için izler.
    private(set) var visibleSongsVersion = 0
    /// Sanatçı → (ada göre sıralı) şarkıları. visibleSongs ile birlikte arka planda hesaplanır.
    private var songsByArtist: [String: [Song]] = [:]

    private var derivedDataTask: Task<Void, Never>?

    /// visibleSongs'tan türeyen her şey — tek seferde arka planda hesaplanır.
    private nonisolated struct DerivedSongData: Sendable {
        let visible: [Song]
        let songsByArtist: [String: [Song]]
        let artists: [String]
        let newArrivals: [Song]
    }

    /// visibleSongs ve ona bağlı dashboard verilerini günceller. allSongs veya blockedUserIDs her değiştiğinde çağrılır.
    /// Arka arkaya gelen değişikliklerde yalnızca en son hesaplama uygulanır.
    private func updateVisibleSongs() {
        let songs = allSongs
        let blocked = Set(blockedUserIDs)
        derivedDataTask?.cancel()
        derivedDataTask = Task { [weak self] in
            // Ağır sort/filter işlemleri background'da — main thread bloklanmaz
            let derived = await Task.detached(priority: .userInitiated) {
                ChordViewModel.deriveSongData(from: songs, blocked: blocked)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.songsByArtist = derived.songsByArtist
            self.visibleSongsVersion += 1
            self.visibleSongs = derived.visible
            self.artists = derived.artists
            self.artistSongCount = derived.songsByArtist.mapValues(\.count)
            self.newArrivals = derived.newArrivals
            self.loadRecentlyPlayed()
            self.updateMostAdded()
            self.resolvePendingDeepLink()
        }
    }

    /// Onaylı (veya eski, status'suz) ve engellenmemiş bir kullanıcıya ait mi?
    private nonisolated static func isPubliclyVisible(_ song: Song, blocked: Set<String>) -> Bool {
        guard song.status == "approved" || song.status == nil else { return false }
        if let ownerId = song.ownerId, !ownerId.isEmpty, blocked.contains(ownerId) { return false }
        return true
    }

    private nonisolated static func deriveSongData(from songs: [Song], blocked: Set<String>) -> DerivedSongData {
        let visible = songs.filter { isPubliclyVisible($0, blocked: blocked) }

        // Sanatçı → şarkılar (ArtistDetailView ve AllArtistsView için önceden hesaplama)
        var songsByArtist: [String: [Song]] = [:]
        for song in visible {
            songsByArtist[song.artist, default: []].append(song)
        }
        for artist in songsByArtist.keys {
            songsByArtist[artist]?.sort { $0.songName.isOrderedBeforeInTurkish($1.songName) }
        }

        // Sanatçıları Türkçe alfabe sırasıyla listele
        let artists = songsByArtist.keys.sorted { $0.isOrderedBeforeInTurkish($1) }

        // Yeni Gelenler (Son 3 ay)
        let threeMonthsAgo = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
        let newArrivals = visible
            .filter { ($0.createdAt ?? .distantPast) > threeMonthsAgo }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }

        return DerivedSongData(visible: visible, songsByArtist: songsByArtist, artists: artists, newArrivals: newArrivals)
    }

    /// Tekil bir şarkı (repertuar, son çalınanlar, deep link) bu kullanıcıya gösterilebilir mi?
    /// Kullanıcının kendi şarkıları taslak/onay bekliyor olsa da görünür.
    private func canShow(_ song: Song, blocked: Set<String>) -> Bool {
        if let ownerId = song.ownerId, !ownerId.isEmpty, ownerId == currentUserId { return true }
        return Self.isPubliclyVisible(song, blocked: blocked)
    }

    /// "En Çok Eklenenler": şarkının kaç paylaşılan repertuarda yer aldığına göre sıralanır.
    private func updateMostAdded() {
        var counts: [String: Int] = [:]
        for repertoire in publicRepertoires {
            for songId in Set(repertoire.songIds) {
                counts[songId, default: 0] += 1
            }
        }
        let blocked = Set(blockedUserIDs)
        mostAdded = counts
            .compactMap { songId, count -> (song: Song, count: Int)? in
                guard let song = songsById[songId], Self.isPubliclyVisible(song, blocked: blocked) else { return nil }
                return (song, count)
            }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.song.songName < $1.song.songName }
            .prefix(10)
            .map(\.song)
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
                // allSongs.didSet → updateVisibleSongs() dashboard verilerini otomatik yeniler
                print("✅ ChordViewModel: \(officialSongs.count) resmi şarkı Storage'dan merge edildi, \(self.cachedUserChords.count) user-chord korundu.")
            }
            .store(in: &cancellables)

        fetchPublicRepertoires()
    }
    
    private func setupAuthListener() {
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                guard let self else { return }
                self.loadUserData()
                if self.publicRepertoiresListener == nil {
                    // Önceki dinleyici (ör. oturum açılmadan önce yetki hatasıyla) düşmüş — yeniden kur
                    self.fetchPublicRepertoires()
                } else if !self.publicRepertoires.isEmpty {
                    self.fetchEditorRepertoires(from: self.publicRepertoires)
                }
            }
        }
    }
    
    private func loadUserData() {
        songPreferences.removeAll()
        if let uid = currentUserId {
            fetchRepertoiresFromFirestore(userId: uid)
            loadBlockedUsersFromFirestore(userId: uid)
            // Bu kullanıcının çevrimdışıyken eklediği, henüz yüklenmemiş şarkıları varsa gönder
            uploadPendingNewSongs()
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
            // Filtre: eski sürümlerde cache'e yanlışlıkla yazılmış resmi şarkıları ayıklar.
            let cachedUserSongs = (syncManager.loadSongsFromCache() ?? []).filter { Self.isUserChord($0.docId) }
            print("📦 ChordViewModel: \(cachedUserSongs.count) user songs loaded from cache.")

            // cachedUserChords'u güncelle — Storage subscription race condition'ını engeller
            self.cachedUserChords = cachedUserSongs

            // Resmi şarkılar Storage'dan henüz gelmediyse sadece cache'i göster
            let storageSongs = ChordsStorageManager.shared.songs.map { $0.toSong() }
            self.allSongs = storageSongs + cachedUserSongs
            // allSongs.didSet → updateVisibleSongs() dashboard verilerini otomatik yeniler
            self.isLoading = false

            // 2. HER AÇILIŞTA Firestore'dan user-chords çek — cache sadece hızlı gösterim için
            // Bu, kullanıcıların şarkılarının her zaman görünmesini garantiler.
            await self.syncUserChords()

            // 3. Bekleyen yazmaları Firestore'a flush et
            if syncManager.hasPendingWrites {
                await syncManager.flushPendingWrites()
            }
        }
    }

    /// Kullanıcı şarkılarını (user-chords) Firestore'dan çekip lokal listeyle birleştirir.
    private func syncUserChords() async {
        guard !isSyncingUserChords else { return }
        isSyncingUserChords = true
        print("🔄 ChordViewModel: Fetching user-chords from Firestore…")
        do {
            let freshUserSongs = try await SyncManager.shared.performFullSync(collectionUserChords: collectionUserChords)

            // Henüz Firestore ID'si almamış (tmp_) lokal şarkılar sync'te kaybolmasın.
            // Yüklemesi tamamlanıp lokalde güncellenememiş olanlar (aynısı sunucuda var) elenir.
            let pendingLocal = allSongs.filter { local in
                local.docId.hasPrefix("tmp_") && !freshUserSongs.contains { $0.hasSameContent(as: local) }
            }
            // Sorgu sürerken ID alan şarkılar sonuca yetişmemiş olabilir — onları da koru
            let freshIds = Set(freshUserSongs.map(\.docId))
            let justUploaded = uploadedDuringSync.filter { !freshIds.contains($0.docId) }

            cachedUserChords = freshUserSongs + justUploaded + pendingLocal
            if !pendingLocal.isEmpty || !justUploaded.isEmpty {
                SyncManager.shared.saveSongsToCache(cachedUserChords)
            }

            // Resmi şarkıları Storage'dan al (hazırsa), user-chords'u tazele
            let storageSongs = ChordsStorageManager.shared.songs.map { $0.toSong() }
            allSongs = storageSongs + cachedUserChords
            print("✅ ChordViewModel: \(freshUserSongs.count) user-chord(s) loaded from Firestore.")
        } catch {
            print("❌ ChordViewModel: Firestore user-chords fetch failed: \(error)")
            // Hata durumunda cache'den yükleme zaten yapıldı, devam edilebilir
        }
        uploadedDuringSync.removeAll()
        isSyncingUserChords = false
        uploadPendingNewSongs()
    }

    /// Pull-to-refresh: kullanıcı şarkılarını ve resmi şarkı kataloğunu yeniler.
    func refresh() async {
        async let catalog: Void = ChordsStorageManager.shared.checkForUpdates(force: true)
        await syncUserChords()
        await catalog
    }

    
    /// Onay bekleyen şarkıları Firestore'dan çeker.
    /// Sadece admin kullanıcılar için çağrılmalı.
    func fetchPendingSongs() async {
        do {
            let snapshot = try await db.collection(collectionUserChords)
                .whereField("status", isEqualTo: "pending")
                .getDocuments()
            pendingSongs = snapshot.documents.compactMap { doc -> Song? in
                if var song = try? doc.data(as: Song.self) {
                    if song.docId.isEmpty { song.docId = doc.documentID }
                    return song
                }
                return nil
            }
        } catch {
            print("❌ fetchPendingSongs: \(error.localizedDescription)")
            // Fallback: client-side filtre
            pendingSongs = allSongs.filter { $0.status == "pending" }
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
        let blocked = Set(blockedUserIDs)
        self.recentlyPlayed = ids.compactMap { songsById[$0] }.filter { canShow($0, blocked: blocked) }
    }
    
    func songsForArtist(_ artist: String) -> [Song] {
        songsByArtist[artist] ?? []
    }

    // MARK: - Deep Link

    /// `gituar://song/<docId>` bağlantısını işler. Şarkılar henüz yüklenmediyse yüklenince açılır.
    func handleDeepLink(_ url: URL) {
        guard url.scheme == "gituar", url.host == "song" else { return }
        let songId = url.lastPathComponent
        guard !songId.isEmpty, songId != "/" else { return }
        pendingDeepLinkSongId = songId
        resolvePendingDeepLink()
    }

    private func resolvePendingDeepLink() {
        guard let songId = pendingDeepLinkSongId, let song = songsById[songId] else { return }
        pendingDeepLinkSongId = nil
        if canShow(song, blocked: Set(blockedUserIDs)) {
            deepLinkedSong = song
        }
    }

    // MARK: - Repertoire Management
    
    private func fetchRepertoiresFromFirestore(userId: String) {
        // Mevcut listener'ları temizle (auth değişimi veya yeniden çağrı durumunda)
        repertoireListeners.forEach { $0.remove() }
        repertoireListeners.removeAll()

        // Private state — snapshot listener verilerini geçici tutar
        var privateReps: [Repertoire] = []
        var myPublicReps: [Repertoire] = []

        // Gizli ↔ herkese açık taşınırken repertuar kısa süre iki listede birden görünebilir — tekilleştir
        func merged() -> [Repertoire] {
            var seenIds = Set<String>()
            return (myPublicReps + privateReps)
                .filter { repertoire in
                    guard let id = repertoire.id else { return true }
                    return seenIds.insert(id).inserted
                }
                .sorted { $0.createdAt > $1.createdAt }
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

    /// Misafir repertuarlarının UserDefaults'ta saklanan hali. Repertoire içindeki @DocumentID yalnızca
    /// Firestore encoder/decoder ile çalışır (JSONEncoder hata verir — misafir repertuarları bu yüzden
    /// hiç kaydedilmiyordu), o yüzden diske bu sade tip yazılır.
    private struct StoredRepertoire: Codable {
        let id: String
        let name: String
        let songIds: [String]
        let createdAt: Date
        let sourceId: String?
    }

    private func loadRepertoires() {
        guard let data = UserDefaults.standard.data(forKey: repertoiresKey),
              let stored = try? JSONDecoder().decode([StoredRepertoire].self, from: data) else {
            // Kayıt yoksa çıkış yapan kullanıcının repertuarları ekranda kalmasın
            self.repertoires = []
            return
        }
        self.repertoires = stored.map {
            Repertoire(id: $0.id, name: $0.name, songIds: $0.songIds, ownerId: "local",
                       createdAt: $0.createdAt, isPublic: false, sourceId: $0.sourceId)
        }
    }
    
    private func saveRepertoires() {
        guard currentUserId == nil else { return }
        let stored = repertoires.map {
            StoredRepertoire(id: $0.id ?? UUID().uuidString, name: $0.name, songIds: $0.songIds,
                             createdAt: $0.createdAt, sourceId: $0.sourceId)
        }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: repertoiresKey)
        }
    }

    @Published var editorRepertoires: [Repertoire] = [] // Editörün seçtiği repertuarlar (Admins)

    private func fetchPublicRepertoires() {
        publicRepertoiresListener?.remove()
        publicRepertoiresListener = db.collection(collectionPublicRepertoires)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                guard let docs = snapshot?.documents else {
                    print("⚠️ fetchPublicRepertoires: \(error?.localizedDescription ?? "snapshot yok")")
                    Task { @MainActor in self.publicRepertoiresListener = nil }
                    return
                }
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
                
                // metadata/admins herkese açıktır (misafir de okur); web ile aynı kaynak. Yoksa users sorgusuna düş.
                var adminIds = (try? await db.collection("metadata").document("admins").getDocument()
                    .data()?["uids"] as? [String]) ?? []
                if adminIds.isEmpty {
                    let snapshot = try await db.collection("users").whereField("isAdmin", isEqualTo: true).getDocuments()
                    adminIds = snapshot.documents.map { $0.documentID }
                }
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
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
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
        let newName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
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

    /// Repertuardaki şarkılar. Silinmiş, engellenen kullanıcılara ait veya
    /// başkasının yayında olmayan şarkıları listelenmez.
    func songs(for repertoire: Repertoire) -> [Song] {
        let blocked = Set(blockedUserIDs)
        return repertoire.songIds
            .compactMap { songsById[$0] }
            .filter { canShow($0, blocked: blocked) }
    }

    /// Şarkı, kullanıcının repertuarlarından en az birinde var mı?
    func isInAnyRepertoire(_ song: Song) -> Bool {
        repertoires.contains { $0.songIds.contains(song.id) }
    }

    func addSong(_ song: Song, to repertoire: Repertoire) {
        let songId = song.id
        
        if let uid = currentUserId, let repId = repertoire.id {
            // arrayUnion: eldeki (eskimiş olabilecek) kopyayı yazmak yerine sunucuda atomik ekler
            let collection = (repertoire.isPublic ?? false) ? collectionPublicRepertoires : "users/\(uid)/repertoires"
            db.collection(collection).document(repId).updateData([
                "songIds": FieldValue.arrayUnion([songId])
            ])
        } else {
            guard let index = repertoires.firstIndex(where: { $0.id == repertoire.id }) else { return }
            if !repertoires[index].songIds.contains(songId) {
                repertoires[index].songIds.append(songId)
                saveRepertoires()
            }
        }
    }
    


    func removeSong(_ song: Song, from repertoire: Repertoire) {
        guard repertoire.ownerId == (currentUserId ?? "local") else { return }
        let songId = song.id
        
        if let uid = currentUserId, let repId = repertoire.id {
            let collection = (repertoire.isPublic ?? false) ? collectionPublicRepertoires : "users/\(uid)/repertoires"
            db.collection(collection).document(repId).updateData([
                "songIds": FieldValue.arrayRemove([songId])
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
        
        // Yeni collection'a yaz + eskisinden sil — tek batch: biri başarısız olursa
        // repertuar ne kaybolur ne de iki yerde birden kalır.
        do {
            let batch = db.batch()
            try batch.setData(from: updatedRepertoire, forDocument: db.collection(newCollection).document(repId))
            batch.deleteDocument(db.collection(oldCollection).document(repId))
            batch.commit { error in
                if let error { print("Error toggling repertoire visibility: \(error)") }
            }
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
        // The real uX ID is assigned by a Firestore transaction. Until then the song lives
        // locally with a unique "tmp_" ID, so it is visible immediately and survives offline.
        var newSong = song
        newSong.docId = "tmp_\(UUID().uuidString)"

        // 1. Save locally immediately
        allSongs.append(newSong)
        persistUserSongs()
        print("✅ saveNewUserSong: Saved locally with tmpId=\(newSong.docId)")

        // 2. Write to Firestore to get the real uX ID
        uploadNewUserSong(newSong)
    }

    /// Kullanıcı şarkılarının kararlı kopyasını ve disk cache'ini günceller.
    private func persistUserSongs() {
        cachedUserChords = allUserSongs
        SyncManager.shared.saveSongsToCache(cachedUserChords)
    }

    /// Henüz Firestore ID'si almamış (tmp_) şarkıları yükler. Çevrimdışı eklenen ya da yüklemesi
    /// yarıda kalan şarkılar için her sync'te ve oturum açılışında tekrar denenir.
    private func uploadPendingNewSongs() {
        // Sync sürerken başlatma — sync bitince zaten çağrılır
        guard let uid = currentUserId, !isSyncingUserChords else { return }
        let pending = allSongs.filter {
            $0.docId.hasPrefix("tmp_") && $0.ownerId == uid && !uploadingTmpIds.contains($0.docId)
        }
        pending.forEach(uploadNewUserSong)
    }

    private func uploadNewUserSong(_ localSong: Song) {
        let tmpId = localSong.docId
        guard !uploadingTmpIds.contains(tmpId) else { return }
        uploadingTmpIds.insert(tmpId)

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
            var finalSong = localSong
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
            Task { @MainActor in
                guard let self = self else { return }
                self.uploadingTmpIds.remove(tmpId)
                if let error = error {
                    // Şarkı lokalde tmp_ ID ile kalır; sonraki sync'te yeniden denenir
                    self.tmpIdsDeletedWhileUploading.remove(tmpId)
                    print("❌ uploadNewUserSong transaction failed: \(error.localizedDescription)")
                } else if let uploadedSong = result as? Song {
                    self.finishUpload(of: uploadedSong, replacing: tmpId)
                }
            }
        }
    }

    /// Transaction sonrası lokaldeki tmp_ kaydı gerçek uX ID'li şarkıyla değiştirir.
    private func finishUpload(of uploadedSong: Song, replacing tmpId: String) {
        let userChordsRef = db.collection(collectionUserChords)

        // Yükleme sürerken kullanıcı şarkıyı sildi → sunucudaki kopyayı da sil
        if tmpIdsDeletedWhileUploading.remove(tmpId) != nil {
            userChordsRef.document(uploadedSong.docId).delete()
            return
        }

        guard let index = allSongs.firstIndex(where: { $0.docId == tmpId }) else {
            // tmp_ kaydı bu arada bir sync tarafından sunucudaki haliyle değiştirilmiş; eksikse ekle
            if songsById[uploadedSong.docId] == nil {
                allSongs.append(uploadedSong)
                persistUserSongs()
            }
            return
        }

        // Yükleme sürerken şarkı düzenlendiyse lokaldeki güncel hali geçerlidir
        let localSong = allSongs[index]
        var finalSong = localSong
        finalSong.docId = uploadedSong.docId
        allSongs[index] = finalSong
        persistUserSongs()
        if isSyncingUserChords { uploadedDuringSync.append(finalSong) }
        print("✅ uploadNewUserSong: Firestore ID assigned: \(finalSong.docId)")

        if !localSong.hasSameContent(as: uploadedSong) || localSong.status != uploadedSong.status {
            do {
                try userChordsRef.document(finalSong.docId).setData(from: finalSong, merge: true)
            } catch {
                print("⚠️ finishUpload: Failed to write edited song: \(error)")
            }
        }
    }
    
    private func updateExistingSong(_ song: Song) {
        // 1. Update local state immediately
        if let index = allSongs.firstIndex(where: { $0.docId == song.docId }) {
            allSongs[index] = song
        }

        // Only user-chords (u* prefix) are written to Firestore.
        // Official songs (numeric docIds) live in Firebase Storage and are read-only here.
        guard Self.isUserChord(song.docId) else {
            print("ℹ️ updateExistingSong: Official song \(song.docId) — local update only, no Firestore write.")
            return
        }

        // 2. Persist user-chords cache
        persistUserSongs()

        // Henüz Firestore ID'si almamış şarkı: yükleme tamamlanınca güncel hali yazılır
        if song.docId.hasPrefix("tmp_") {
            uploadPendingNewSongs()
            return
        }

        // 3. Firestore'a hemen yaz. Çevrimdışıysa Firestore SDK yazmayı kendi kalıcı kuyruğunda
        // tutar ve bağlantı gelince gönderir — düzenleme (ve "Yayınla") bir sonraki açılışı beklemez.
        do {
            try db.collection(collectionUserChords).document(song.docId).setData(from: song, merge: true)
        } catch {
            print("⚠️ updateExistingSong: Failed to encode song: \(error)")
        }
    }

    func deleteSong(_ song: Song) {
        let songId = song.id

        // 1. Remove from local state immediately
        allSongs.removeAll { $0.docId == songId }
        pendingSongs.removeAll { $0.docId == songId }

        if songId.hasPrefix("tmp_") {
            // Henüz sunucuya yazılmadı — lokal silmek yeterli.
            // Yüklemesi sürüyorsa işaretle; finishUpload sunucudaki kopyayı temizler.
            if uploadingTmpIds.contains(songId) {
                tmpIdsDeletedWhileUploading.insert(songId)
            }
            persistUserSongs()
        } else if songId.hasPrefix("u") {
            // 2. Persist user-chords cache
            persistUserSongs()

            // 3. Immediately delete from Firestore (Admin / User action should reflect promptly)
            Task {
                do {
                    try await db.collection(collectionUserChords).document(songId).delete()
                    print("✅ deleteSong: User chord \(songId) deleted directly from Firestore.")
                } catch {
                    // Fallback to queue
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
                    // Silinemedi (yetki/bağlantı) — şarkı Storage'da duruyor, listeye geri koy
                    self.allSongs = ChordsStorageManager.shared.songs.map { $0.toSong() } + self.cachedUserChords
                }
            }
        }
    }
    
    func approveSong(_ song: Song) {
        setStatus("approved", for: song)
    }

    func rejectSong(_ song: Song) {
        setStatus("rejected", for: song)
    }

    private func setStatus(_ status: String, for song: Song) {
        let songId = song.id
        let collection = songId.hasPrefix("u") ? collectionUserChords : collectionChords

        // Update local state + user-chords cache
        if let index = allSongs.firstIndex(where: { $0.id == songId }) {
            allSongs[index].status = status
            persistUserSongs()
        }
        pendingSongs.removeAll { $0.id == songId }

        // Admin decision must reach Firestore promptly, so write immediately
        Task {
            do {
                try await db.collection(collection).document(songId).updateData(["status": status])
            } catch {
                // On failure, queue for later
                let write = PendingWrite(collection: collection, documentId: songId,
                                         operation: .update, fields: ["status": .string(status)])
                SyncManager.shared.enqueuePendingWrite(write)
                print("⚠️ setStatus(\(status)): Direct write failed, queued. \(error)")
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


struct UserSongPreference: Codable, Equatable, Sendable {
    var songId: String
    var selectedKeyRoot: String
    var capoFret: Int
    var note: String
}

