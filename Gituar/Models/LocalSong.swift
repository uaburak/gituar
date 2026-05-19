import Foundation

// MARK: - LocalSong
//
// Firebase Storage'daki chords_data.json dosyasında kayıtlar TAM key isimleriyle saklanır:
//
//   { "docId": "1", "artist": "...", "songName": "...", "originalKey": "Am", "content": "...", "addedBy": "..." }
//
// Tüm lokal arama, filtreleme ve detay gösterme işlemleri bu model üzerinden yapılır.
// Kullanıcıların kendi eklediği şarkılar (user_chords) bu modeli KULLANMAZ — onlar
// zaten ChordViewModel / SyncManager tarafından Song modeli ile yönetilmektedir.

struct LocalSong: Identifiable, Codable, Hashable, Sendable {

    // MARK: - Fields

    let docId: String
    let artist: String
    let songName: String
    let originalKey: String
    let content: String
    let addedBy: String?

    // MARK: - Identifiable

    var id: String { docId }

    // MARK: - CodingKeys — JSON'daki gerçek key isimleriyle eşleşir

    enum CodingKeys: String, CodingKey {
        case docId
        case artist
        case songName
        case originalKey
        case content
        case addedBy
    }

    // MARK: - Hashable & Equatable

    func hash(into hasher: inout Hasher) { hasher.combine(docId) }
    static func == (lhs: LocalSong, rhs: LocalSong) -> Bool { lhs.docId == rhs.docId }
}

// MARK: - LocalSong → Song bridge

extension LocalSong {
    /// LocalSong → Song dönüşümü. Sadece Storage'dan gelen resmi şarkılar için kullanılır.
    func toSong() -> Song {
        Song(
            docId: docId,
            artist: artist,
            songName: songName,
            originalKey: originalKey,
            content: content,
            addedBy: addedBy
        )
    }
}

extension Song {
    /// Song → LocalSong dönüşümü (ihtiyaç duyulursa).
    func toLocalSong() -> LocalSong {
        LocalSong(
            docId: docId,
            artist: artist,
            songName: songName,
            originalKey: originalKey,
            content: content,
            addedBy: addedBy
        )
    }
}
