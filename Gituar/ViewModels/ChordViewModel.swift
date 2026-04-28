import Foundation
import FirebaseFirestore
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
    @Published var favoriteSongs: [Song] = []
    @Published var artists: [String] = [] // Sanatçı listesi
    
    private var allSongs: [Song] = []
    private var db = Firestore.firestore()
    private var cancellables = Set<AnyCancellable>()
    private let recentPlayedKey = "recentlyPlayedIds"
    private let repertoiresKey = "user_repertoires"
    private let favoritesKey = "favoriteSongIds"
    
    init() {
        loadRepertoires()
        loadFavorites()
        fetchAllSongs()
        
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] text in
                self?.filterSongs(query: text)
            }
            .store(in: &cancellables)
    }
    
    private func fetchAllSongs() {
        isLoading = true
        db.collection("chords").getDocuments { [weak self] snapshot, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                
                if let docs = snapshot?.documents {
                    self.allSongs = docs.compactMap { try? $0.data(as: Song.self) }
                    self.processDashboardData()
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
    
    // MARK: - Favorites Management
    
    private func loadFavorites() {
        let ids = UserDefaults.standard.stringArray(forKey: favoritesKey) ?? []
        self.favoriteSongs = ids.compactMap { id in
            allSongs.first { ($0.id ?? $0.docId) == id }
        }
    }
    
    func toggleFavorite(song: Song) {
        var ids = UserDefaults.standard.stringArray(forKey: favoritesKey) ?? []
        let songId = song.id ?? song.docId
        
        if ids.contains(songId) {
            ids.removeAll { $0 == songId }
        } else {
            ids.insert(songId, at: 0)
        }
        
        UserDefaults.standard.set(ids, forKey: favoritesKey)
        loadFavorites()
    }
    
    func isFavorite(song: Song) -> Bool {
        let ids = UserDefaults.standard.stringArray(forKey: favoritesKey) ?? []
        let songId = song.id ?? song.docId
        return ids.contains(songId)
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
    
    private func loadRepertoires() {
        if let data = UserDefaults.standard.data(forKey: repertoiresKey),
           let saved = try? JSONDecoder().decode([Repertoire].self, from: data) {
            self.repertoires = saved
        }
    }
    
    private func saveRepertoires() {
        if let data = try? JSONEncoder().encode(repertoires) {
            UserDefaults.standard.set(data, forKey: repertoiresKey)
        }
    }

    func addRepertoire(name: String) {
        let newRepertoire = Repertoire(
            id: UUID().uuidString,
            name: name,
            songIds: [],
            ownerId: "local",
            createdAt: Date()
        )
        repertoires.append(newRepertoire)
        saveRepertoires()
    }
    
    func deleteRepertoire(at offsets: IndexSet) {
        repertoires.remove(atOffsets: offsets)
        saveRepertoires()
    }

    func songs(for repertoire: Repertoire) -> [Song] {
        return repertoire.songIds.compactMap { id in
            allSongs.first { ($0.id ?? $0.docId) == id }
        }
    }

    func addSong(_ song: Song, to repertoire: Repertoire) {
        guard let index = repertoires.firstIndex(where: { $0.id == repertoire.id }) else { return }
        let songId = song.id ?? song.docId
        if !repertoires[index].songIds.contains(songId) {
            repertoires[index].songIds.append(songId)
            saveRepertoires()
        }
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

