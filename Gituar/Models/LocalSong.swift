import Foundation

// MARK: - LocalSong
//
// Firebase Storage'daki chords_data.json dosyasında kayıtlar TAM key isimleriyle saklanır:
//
//   { "docId": "1", "artist": "...", "songName": "...", "originalKey": "Am", "content": "...", "addedBy": "...", "ownerId": "..." }
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
    let ownerId: String?
    /// JSON'daki "createdAt" alanı (sayı ya da ISO8601 metin). "Yeni Eklenenler" için gerekli.
    let createdAt: Date?
    /// Resmi şarkılar hep "approved" — "Onay bekleyen" filtresini geçer.
    let status: String?

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
        case ownerId
        case createdAt
        case status
    }

    // MARK: - Hashable & Equatable

    func hash(into hasher: inout Hasher) { hasher.combine(docId) }
    static func == (lhs: LocalSong, rhs: LocalSong) -> Bool { lhs.docId == rhs.docId }
}

// MARK: - Decoding

extension LocalSong {
    /// `createdAt` hem JSONEncoder'ın varsayılan sayı biçimini hem de ISO8601 metni kabul eder;
    /// tek bir kayıttaki tarih biçimi tüm kataloğun decode edilmesini bozmasın.
    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        docId       = try c.decode(String.self, forKey: .docId)
        artist      = try c.decode(String.self, forKey: .artist)
        songName    = try c.decode(String.self, forKey: .songName)
        originalKey = try c.decode(String.self, forKey: .originalKey)
        content     = try c.decode(String.self, forKey: .content)
        addedBy     = try c.decodeIfPresent(String.self, forKey: .addedBy)
        ownerId     = try c.decodeIfPresent(String.self, forKey: .ownerId)
        status      = try c.decodeIfPresent(String.self, forKey: .status)
        if !c.contains(.createdAt) {
            createdAt = nil
        } else if let seconds = try? c.decode(Double.self, forKey: .createdAt) {
            createdAt = Date(timeIntervalSinceReferenceDate: seconds)
        } else if let text = try? c.decode(String.self, forKey: .createdAt) {
            createdAt = try? Date(text, strategy: .iso8601)
        } else {
            createdAt = nil
        }
    }
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
            createdAt: createdAt,
            ownerId: ownerId,
            addedBy: addedBy,
            status: status ?? "approved"  // resmi şarkılar her zaman onaylanış
        )
    }
}
