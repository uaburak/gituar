import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine
import SwiftUI

// MARK: - ChordViewModel
//
// Şarkılar uygulamada tutulmaz: listeler, sanatçılar, arama ve şarkı içeriği istendiğinde Gituar API'sinden
// (Cloudflare D1) çekilir (`GituarAPI`). Burada yalnızca küçük bir bellek içi önbellek vardır.
// Firebase yalnızca kimlik ve kişisel veriler içindir: repertuarlar, şarkı tercihleri (ton/kapo/not),
// engellenen kullanıcılar, herkese açık repertuarlar (editörün seçimleri) ve şikayetler.

@MainActor
class ChordViewModel: ObservableObject {

    // MARK: Kişisel veriler (Firestore / UserDefaults)

    @Published var repertoires: [Repertoire] = []
    @Published var publicRepertoires: [Repertoire] = []
    @Published var editorRepertoires: [Repertoire] = [] // Editörün seçtiği repertuarlar (yöneticilerin herkese açık repertuarları)
    @Published var songPreferences: [String: UserSongPreference] = [:] // Kullanıcıya özel şarkı ayarları

    @Published var blockedUserIDs: [String] = [] {
        didSet { UserDefaults.standard.set(blockedUserIDs, forKey: "blockedUserIDs") }
    }

    // MARK: API'den gelenler

    /// Giriş yapmış kullanıcının kendi şarkıları (tüm durumlar).
    @Published private(set) var mySongs: [Song] = []
    @Published private(set) var isLoadingMySongs = false
    @Published private(set) var mySongsError: String?

    /// Onay bekleyen şarkılar (yönetici).
    @Published var pendingSongs: [Song] = []
    @Published private(set) var pendingError: String?

    /// `gituar://song/<id>` bağlantısıyla açılan şarkı — HomeView bu değere göre şarkıyı push eder.
    @Published var deepLinkedSong: Song?

    private let collectionPublicRepertoires = "public-repertoires"

    private var db = Firestore.firestore()
    private var authListener: AuthStateDidChangeListenerHandle?
    private var adminIdsCache: [String]? = nil
    /// Aktif Firestore snapshot listener'larını tutar — auth değişiminde remove() ile temizlenir.
    private var repertoireListeners: [ListenerRegistration] = []
    /// Public repertuar dinleyicisi. Hata alırsa Firestore dinleyiciyi kapatır; nil'e çekilip auth değişiminde yeniden kurulur.
    private var publicRepertoiresListener: ListenerRegistration?
    private var lastAuthUid: String?

    private let recentPlayedKey = "recentlyPlayedIds"
    private let repertoiresKey  = "user_repertoires"

    // MARK: Önbellek

    /// İçeriği yüklenmiş şarkılar (id → tam kayıt).
    private var fullSongCache: [String: Song] = [:]
    /// Sanatçı sayfaları (slug → detay).
    private var artistCache: [String: GituarAPI.ArtistDetail] = [:]

    var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    init() {
        self.blockedUserIDs = UserDefaults.standard.stringArray(forKey: "blockedUserIDs") ?? []
        LegacyCatalogCleanup.runOnce()
        setupAuthListener()
        fetchPublicRepertoires()
    }

    private func setupAuthListener() {
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            let uid = user?.uid
            DispatchQueue.main.async {
                guard let self else { return }
                let changed = uid != self.lastAuthUid
                self.lastAuthUid = uid
                self.loadUserData(userChanged: changed)
                if self.publicRepertoiresListener == nil {
                    // Önceki dinleyici (ör. oturum açılmadan önce yetki hatasıyla) düşmüş — yeniden kur
                    self.fetchPublicRepertoires()
                } else if !self.publicRepertoires.isEmpty {
                    self.fetchEditorRepertoires(from: self.publicRepertoires)
                }
            }
        }
    }

    private func loadUserData(userChanged: Bool) {
        songPreferences.removeAll()
        if userChanged {
            // Önceki kullanıcının (sahibi/yöneticisi olarak gördüğü) onaysız şarkıları önbellekte kalmasın
            fullSongCache = fullSongCache.filter { $0.value.status == "approved" || $0.value.status == nil }
            mySongs = []
            pendingSongs = []
        }
        if let uid = currentUserId {
            fetchRepertoiresFromFirestore(userId: uid)
            loadBlockedUsersFromFirestore(userId: uid)
            Task { await loadMySongs() }
        } else {
            // Guest mode veya çıkış — listener'ları temizle
            repertoireListeners.forEach { $0.remove() }
            repertoireListeners.removeAll()
            loadRepertoires()
        }
    }

    // MARK: - Şarkı erişimi (API + önbellek)

    /// Liste kaydını (içeriksiz) tam kayda tamamlar. Önbellekte varsa ağa gitmez.
    func fullSong(for song: Song, forceReload: Bool = false) async throws -> Song {
        if !forceReload {
            if let cached = fullSongCache[song.docId] { return song.hasContent ? song : song.merged(with: cached) }
            if song.hasContent { return song }
        }
        let full = try await GituarAPI.shared.song(id: song.docId)
        let merged = song.merged(with: full)
        fullSongCache[song.docId] = merged
        return merged
    }

    /// Kimliği bilinen şarkıyı (içerikle) getirir.
    func song(id: String) async throws -> Song {
        if let cached = fullSongCache[id] { return cached }
        let full = try await GituarAPI.shared.song(id: id)
        fullSongCache[id] = full
        return full
    }

    /// Kimlik listesini (sırayı koruyarak) şarkılara çevirir. Silinmiş/olmayan şarkılar atlanır.
    /// Kullanıcının kendi (henüz onaylanmamış) şarkıları `mySongs`'tan tamamlanır.
    func songs(ids: [String]) async throws -> [Song] {
        guard !ids.isEmpty else { return [] }
        let fetched = try await GituarAPI.shared.songs(ids: ids)
        var byId = Dictionary(fetched.map { ($0.docId, $0) }, uniquingKeysWith: { first, _ in first })
        for own in mySongs where byId[own.docId] == nil { byId[own.docId] = own }
        var seen = Set<String>()
        return ids.compactMap { id in
            guard seen.insert(id).inserted, let song = byId[id], !isBlocked(song) else { return nil }
            return song
        }
    }

    /// Repertuardaki şarkılar. Silinmiş, engellenen kullanıcılara ait veya yayında olmayan şarkılar listelenmez.
    func songs(for repertoire: Repertoire) async throws -> [Song] {
        try await songs(ids: repertoire.songIds)
    }

    /// Sanatçı sayfası (önbellekli).
    func artistDetail(slug: String, forceReload: Bool = false) async throws -> GituarAPI.ArtistDetail {
        if !forceReload, let cached = artistCache[slug] { return cached }
        let detail = try await GituarAPI.shared.artist(slug: slug)
        artistCache[slug] = detail
        return detail
    }

    /// Engellenen bir kullanıcıya mı ait? (Sahip bilgisi yalnızca tam kayıtta bulunur.)
    func isBlocked(_ song: Song) -> Bool {
        guard let ownerId = song.ownerId, !ownerId.isEmpty, ownerId != currentUserId else { return false }
        return blockedUserIDs.contains(ownerId)
    }

    // MARK: - Son Çalınanlar

    var recentlyPlayedIds: [String] {
        UserDefaults.standard.stringArray(forKey: recentPlayedKey) ?? []
    }

    func addToRecentlyPlayed(_ song: Song) {
        var ids = recentlyPlayedIds
        ids.removeAll { $0 == song.docId }
        ids.insert(song.docId, at: 0)
        UserDefaults.standard.set(Array(ids.prefix(20)), forKey: recentPlayedKey)
    }

    func recentlyPlayedSongs() async throws -> [Song] {
        let ids = recentlyPlayedIds
        let songs = try await songs(ids: ids)
        // Artık var olmayan (silinmiş / eski katalog) kimlikleri listeden temizle
        let alive = Set(songs.map(\.docId))
        let missing = ids.filter { !alive.contains($0) }
        if !missing.isEmpty {
            let kept = recentlyPlayedIds.filter { alive.contains($0) || !ids.contains($0) }
            UserDefaults.standard.set(kept, forKey: recentPlayedKey)
        }
        return songs
    }

    // MARK: - Popülerlik

    /// Şarkı açıldı — "view" kaydı (oturumsuz da, cihaz kimliğiyle).
    func trackView(_ song: Song) {
        GituarAPI.shared.track(.view, songId: song.docId)
    }

    private func isFavorites(_ repertoire: Repertoire) -> Bool {
        repertoire.name.trimmingCharacters(in: .whitespaces).turkeyNormalized == "favoriler"
    }

    /// Şarkı bir repertuara eklendi: "Favoriler" → favorite, diğerleri → repertoire.
    private func trackAdded(songId: String, to repertoire: Repertoire) {
        GituarAPI.shared.track(isFavorites(repertoire) ? .favorite : .repertoire, songId: songId, active: true)
    }

    /// Şarkı bir repertuardan çıkarıldı. Puan, şarkı aynı türde başka bir listede kalmadıysa geri alınır.
    private func trackRemoved(songId: String, from repertoire: Repertoire) {
        let favorite = isFavorites(repertoire)
        let stillPresent = repertoires.contains { other in
            other.id != repertoire.id && isFavorites(other) == favorite && other.songIds.contains(songId)
        }
        guard !stillPresent else { return }
        GituarAPI.shared.track(favorite ? .favorite : .repertoire, songId: songId, active: false)
    }

    // MARK: - Deep Link

    /// `gituar://song/<id>` bağlantısını işler: şarkı API'den çekilip açılır.
    func handleDeepLink(_ url: URL) {
        guard url.scheme == "gituar", url.host == "song" else { return }
        let songId = url.lastPathComponent
        guard !songId.isEmpty, songId != "/" else { return }
        Task {
            do {
                let song = try await self.song(id: songId)
                if !isBlocked(song) { deepLinkedSong = song }
            } catch {
                print("⚠️ handleDeepLink(\(songId)): \(error.localizedDescription)")
            }
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

        let l1 = db.collection("users").document(userId).collection("repertoires")
            .addSnapshotListener { [weak self] snapshot, error in
                // Firestore dinleyicileri ana kuyrukta çağrılır
                guard let self, let snapshot, error == nil else { return }
                privateReps = snapshot.documents.compactMap { try? $0.data(as: Repertoire.self) }
                self.repertoires = merged()
            }
        repertoireListeners.append(l1)

        let l2 = db.collection(collectionPublicRepertoires)
            .whereField("ownerId", isEqualTo: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                // Firestore dinleyicileri ana kuyrukta çağrılır
                guard let self, let snapshot, error == nil else { return }
                myPublicReps = snapshot.documents.compactMap { try? $0.data(as: Repertoire.self) }
                self.repertoires = merged()
            }
        repertoireListeners.append(l2)
    }

    /// Misafir repertuarlarının UserDefaults'ta saklanan hali. Repertoire içindeki @DocumentID yalnızca
    /// Firestore encoder/decoder ile çalışır, o yüzden diske bu sade tip yazılır.
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

    private func fetchPublicRepertoires() {
        publicRepertoiresListener?.remove()
        publicRepertoiresListener = db.collection(collectionPublicRepertoires)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let docs = snapshot?.documents else {
                    print("⚠️ fetchPublicRepertoires: \(error?.localizedDescription ?? "snapshot yok")")
                    DispatchQueue.main.async { self?.publicRepertoiresListener = nil }
                    return
                }
                let repertoires = docs.compactMap { try? $0.data(as: Repertoire.self) }
                    .sorted { $0.createdAt > $1.createdAt }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.publicRepertoires = repertoires
                    self.fetchEditorRepertoires(from: repertoires)
                }
            }
    }

    private func fetchEditorRepertoires(from allPublic: [Repertoire]) {
        Task {
            if let cached = adminIdsCache {
                self.editorRepertoires = allPublic.filter { cached.contains($0.ownerId) }
                return
            }
            do {
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
            onProgress(index + 1, total)
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

    /// Yeni kullanıcı için 4 sabit varsayılan repertuarı oluşturur ("Favoriler" favori listesidir).
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
        // Repertuarla birlikte giden şarkıların popülerlik puanı geri alınır
        if repertoire.ownerId == (currentUserId ?? "local") {
            for songId in Set(repertoire.songIds) { trackRemoved(songId: songId, from: repertoire) }
        }
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

    /// Şarkı, kullanıcının repertuarlarından en az birinde var mı?
    func isInAnyRepertoire(_ song: Song) -> Bool {
        repertoires.contains { $0.songIds.contains(song.id) }
    }

    func addSong(_ song: Song, to repertoire: Repertoire) {
        let songId = song.id
        guard !repertoire.songIds.contains(songId) else { return }
        trackAdded(songId: songId, to: repertoire)

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
        trackRemoved(songId: songId, from: repertoire)

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
        // Kullanıcının listelerinde henüz olmayan şarkılar için "repertoire" puanı
        let alreadyListed = Set(repertoires.flatMap(\.songIds))
        for songId in Set(repertoire.songIds) where !alreadyListed.contains(songId) {
            trackAdded(songId: songId, to: copy)
        }

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

    // MARK: - Blocking

    /// Bir kullanıcıyı engeller — hem local state hem Firestore'a yazar.
    func blockUser(ownerId: String) {
        guard !blockedUserIDs.contains(ownerId) else { return }
        blockedUserIDs.append(ownerId) // didSet → UserDefaults
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
                    self.blockedUserIDs = blocked
                }
            } catch {
                print("⚠️ loadBlockedUsersFromFirestore: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Kullanıcı şarkıları (API)

    func loadMySongs() async {
        guard currentUserId != nil else {
            mySongs = []
            return
        }
        isLoadingMySongs = true
        defer { isLoadingMySongs = false }
        do {
            let songs = try await GituarAPI.shared.mySongs()
            mySongs = songs.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            mySongsError = nil
            for song in songs where song.hasContent { fullSongCache[song.docId] = song }
        } catch is CancellationError {
        } catch {
            mySongsError = error.localizedDescription
            print("⚠️ loadMySongs: \(error.localizedDescription)")
        }
    }

    /// Yeni şarkı oluşturur ya da mevcut şarkıyı günceller. Hata mesajı (ör. 422 uygunsuz içerik) fırlatılır.
    @discardableResult
    func saveSong(existingId: String?, input: GituarAPI.SongInput) async throws -> Song {
        let saved: Song
        if let existingId, !existingId.isEmpty {
            saved = try await GituarAPI.shared.updateSong(id: existingId, input)
        } else {
            saved = try await GituarAPI.shared.createSong(input)
        }
        fullSongCache[saved.docId] = saved
        if let index = mySongs.firstIndex(where: { $0.docId == saved.docId }) {
            mySongs[index] = saved
        } else {
            mySongs.insert(saved, at: 0)
        }
        artistCache.removeAll()
        return saved
    }

    /// Şarkıyı herkes için kalıcı olarak siler (sahibi ya da yönetici). Zaten silinmişse (404) başarılı sayılır.
    func deleteSong(id songId: String) async throws {
        do {
            try await GituarAPI.shared.deleteSong(id: songId)
        } catch let error as GituarAPIError where error.isNotFound {
            // Zaten yok
        }
        forget(songId: songId)
    }

    private func forget(songId: String) {
        fullSongCache.removeValue(forKey: songId)
        mySongs.removeAll { $0.docId == songId }
        pendingSongs.removeAll { $0.docId == songId }
        artistCache.removeAll()
    }

    // MARK: - Yönetici: onay

    /// Onay bekleyen şarkıları API'den çeker. Sadece admin kullanıcılar için çağrılmalı.
    func fetchPendingSongs() async {
        do {
            pendingSongs = try await GituarAPI.shared.pendingSongs()
            pendingError = nil
            for song in pendingSongs where song.hasContent { fullSongCache[song.docId] = song }
        } catch is CancellationError {
        } catch {
            pendingError = error.localizedDescription
            print("❌ fetchPendingSongs: \(error.localizedDescription)")
        }
    }

    func approveSong(_ song: Song) async throws {
        try await setStatus("approved", for: song)
    }

    func rejectSong(_ song: Song) async throws {
        try await setStatus("rejected", for: song)
    }

    private func setStatus(_ status: String, for song: Song) async throws {
        try await GituarAPI.shared.setStatus(id: song.docId, status: status)
        pendingSongs.removeAll { $0.docId == song.docId }
        if var cached = fullSongCache[song.docId] {
            cached.status = status
            fullSongCache[song.docId] = cached
        }
        artistCache.removeAll()
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

// MARK: - Eski katalog dosyalarının temizliği

/// Önceki sürümlerin cihaza yazdığı katalog kopyası (13 bin şarkı), kullanıcı şarkısı önbelleği ve
/// bekleyen yazma kuyruğu artık kullanılmıyor — bir kez silinir.
private enum LegacyCatalogCleanup {
    static func runOnce() {
        let key = "legacyCatalogCleanupDone"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        Task.detached(priority: .background) {
            guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            for name in ["catalog_cache.deflate", "songs_cache.json", "pending_writes.json", "chords_data.json"] {
                try? FileManager.default.removeItem(at: docs.appendingPathComponent(name))
            }
        }
        for key in ["catalog.bundleBuild", "catalog.cacheSeq"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
