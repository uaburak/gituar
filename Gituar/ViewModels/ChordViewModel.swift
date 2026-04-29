import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine
import SwiftUI

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
    
    init() {
        setupAuthListener()
        fetchAllSongs()
        
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] text in
                self?.filterSongs(query: text)
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
    
    private func fetchAllSongs() {
        guard allSongs.isEmpty && !isLoading else { return }
        
        isLoading = true
        db.collection("chords").getDocuments { [weak self] snapshot, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                
                if let docs = snapshot?.documents {
                    let fetchedSongs = docs.compactMap { try? $0.data(as: Song.self) }
                    self.allSongs = fetchedSongs
                    self.processDashboardData()
                    self.loadUserData(userId: self.userId)
                }
            }
        }
    }
    
    private func processDashboardData() {
        // Sanatçıları alfabetik listele
        self.artists = Array(Set(allSongs.map { $0.artist })).sorted()
        
        // En çok eklenenler (repertoireAdds'e göre)
        self.mostAdded = allSongs.sorted { ($0.repertoireAdds ?? 0) > ($1.repertoireAdds ?? 0) }.prefix(10).map { $0 }
        
        // Popülerler (Ağırlıklı Algoritma - popularityScore'a göre)
        // Score = (TotalViews * 0.1) + (RecentViews * 0.6) + (RepertoireAdds * 0.3)
        self.popularChords = allSongs.sorted { $0.popularityScore > $1.popularityScore }.prefix(10).map { $0 }
        
        // Yeni Gelenler (Son 3 ay)
        let threeMonthsAgo = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
        self.newArrivals = allSongs.filter { ($0.createdAt ?? Date(timeIntervalSince1970: 0)) > threeMonthsAgo }
            .sorted { ($0.createdAt ?? Date()) > ($1.createdAt ?? Date()) }
        
        // Son Çalınanlar (UserDefaults'tan yükle)
        loadRecentlyPlayed()
    }

    
    func addToRecentlyPlayed(_ song: Song) {
        var ids = UserDefaults.standard.stringArray(forKey: recentPlayedKey) ?? []
        let songId = song.id ?? song.docId
        
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
            allSongs.first { ($0.id ?? $0.docId) == id }
        }
    }
    
    func songsForArtist(_ artist: String) -> [Song] {
        allSongs.filter { $0.artist == artist }.sorted { $0.songName < $1.songName }
    }
    
    func filterSongs(query: String) {
        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedQuery.isEmpty else {
            self.songs = []
            return
        }
        
        let normalizedQuery = cleanedQuery.turkeyNormalized
        let queryWords = normalizedQuery.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        
        let filtered = allSongs.filter { song in
            let normalizedArtist = song.artist.turkeyNormalized
            let normalizedSongName = song.songName.turkeyNormalized
            
            return queryWords.allSatisfy { word in
                normalizedArtist.contains(word) || normalizedSongName.contains(word)
            }
        }
        
        self.songs = filtered.sorted { s1, s2 in
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
    }
    
    func incrementViewCount(for song: Song) {
        let songId = song.id ?? song.docId
        let docRef = db.collection("chords").document(songId)
        
        docRef.updateData([
            "totalViews": FieldValue.increment(Int64(1)),
            "recentViews": FieldValue.increment(Int64(1))
        ])
    }

    // MARK: - Repertoire Management
    
    private func fetchRepertoiresFromFirestore(userId: String) {
        db.collection("users").document(userId).collection("repertoires").addSnapshotListener { [weak self] snapshot, _ in
            guard let self = self, let docs = snapshot?.documents else { return }
            DispatchQueue.main.async {
                self.repertoires = docs.compactMap { try? $0.data(as: Repertoire.self) }
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

    func fetchPublicRepertoires() {
        db.collectionGroup("repertoires")
            .whereField("isPublic", isEqualTo: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self, let docs = snapshot?.documents else { return }
                DispatchQueue.main.async {
                    self.publicRepertoires = docs.compactMap { try? $0.data(as: Repertoire.self) }
                        .sorted { ($0.createdAt ) > ($1.createdAt ) }
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
        if let uid = userId {
            if let id = repertoire.id {
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
            db.collection("users").document(uid).collection("repertoires").document(repId).updateData([
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
            allSongs.first { ($0.id ?? $0.docId) == id }
        }
    }

    func addSong(_ song: Song, to repertoire: Repertoire) {
        let songId = song.id ?? song.docId
        
        if let uid = userId, let repId = repertoire.id {
            var updatedSongIds = repertoire.songIds
            if !updatedSongIds.contains(songId) {
                updatedSongIds.append(songId)
                db.collection("users").document(uid).collection("repertoires").document(repId).updateData([
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
        let songId = song.id ?? song.docId
        
        if let uid = userId, let repId = repertoire.id {
            var updatedSongIds = repertoire.songIds
            updatedSongIds.removeAll { $0 == songId }
            db.collection("users").document(uid).collection("repertoires").document(repId).updateData([
                "songIds": updatedSongIds
            ])
        } else {
            guard let index = repertoires.firstIndex(where: { $0.id == repertoire.id }) else { return }
            repertoires[index].songIds.removeAll { $0 == songId }
            saveRepertoires()
        }
    }

    func setRepertoirePublic(_ repertoire: Repertoire, isPublic: Bool) {
        guard repertoire.ownerId == (userId ?? "local") else { return }
        if let uid = userId, let repId = repertoire.id {
            db.collection("users").document(uid).collection("repertoires").document(repId).updateData([
                "isPublic": isPublic
            ])
        } else {
            guard let index = repertoires.firstIndex(where: { $0.id == repertoire.id }) else { return }
            repertoires[index].isPublic = isPublic
            saveRepertoires()
        }
    }

    func duplicateRepertoire(_ repertoire: Repertoire) {
        guard !isRepertoireCopied(repertoire) else { return }
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
        do {
            let docRef = db.collection("chords").document(song.docId)
            try docRef.setData(from: song)
            
            // Update local state
            if let index = allSongs.firstIndex(where: { $0.docId == song.docId }) {
                allSongs[index] = song
            } else {
                allSongs.append(song)
            }
            processDashboardData()
        } catch {
            print("Error saving song: \(error)")
        }
    }

    func deleteSong(_ song: Song) {
        let songId = song.id ?? song.docId
        db.collection("chords").document(songId).delete() { [weak self] error in
            if error == nil {
                DispatchQueue.main.async {
                    self?.allSongs.removeAll { $0.docId == songId || $0.id == songId }
                    self?.processDashboardData()
                }
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
        if let uid = userId {
            db.collection("users").document(uid).collection("preferences").document(songId).getDocument { [weak self] snapshot, _ in
                DispatchQueue.main.async {
                    if let data = try? snapshot?.data(as: UserSongPreference.self) {
                        self?.songPreferences[songId] = data
                        // Update local cache
                        let currentPrefKey = self?.getPrefKey(for: songId) ?? "pref_guest_\(songId)"
                        if let encoded = try? JSONEncoder().encode(data) {
                            UserDefaults.standard.set(encoded, forKey: currentPrefKey)
                        }
                    }
                }
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
    var turkeyNormalized: String {
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

struct UserSongPreference: Codable, Equatable {
    var songId: String
    var selectedKeyRoot: String
    var capoFret: Int
    var note: String
}

