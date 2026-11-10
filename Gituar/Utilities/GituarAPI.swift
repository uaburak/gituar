import Foundation
import FirebaseAuth

// MARK: - GituarAPI
//
// Tüm şarkılar Cloudflare Worker + D1 üzerindeki Gituar API'sinden gelir (pakette katalog yok).
// Okuma uçları herkese açık; yazma uçları `Authorization: Bearer <Firebase ID token>` ister.
// Hatalar `{ "error": "mesaj" }` biçimindedir.

nonisolated enum GituarAPIError: LocalizedError, Sendable {
    /// İnternet yok / sunucuya ulaşılamadı
    case offline
    /// Giriş gerekiyor ama oturum yok
    case notSignedIn
    /// Sunucu bir hata döndü (`{ error }` mesajıyla)
    case server(status: Int, message: String?)
    /// Yanıt beklenen biçimde değil
    case invalidResponse

    var status: Int? {
        if case .server(let status, _) = self { return status }
        return nil
    }

    var isNotFound: Bool { status == 404 }

    var errorDescription: String? {
        switch self {
        case .offline:
            return "İnternet bağlantısı yok gibi görünüyor. Bağlantını kontrol edip tekrar dene."
        case .notSignedIn:
            return "Bu işlem için giriş yapman gerekiyor."
        case .server(let status, let message):
            if let message, !message.isEmpty { return message }
            switch status {
            case 401: return "Oturumun doğrulanamadı. Çıkış yapıp tekrar giriş yapmayı dene."
            case 403: return "Bu işlem için yetkin yok."
            case 404: return "Şarkı bulunamadı. Kaldırılmış olabilir."
            case 422: return "İçerik uygunsuz ifade içeriyor ve gönderilemedi."
            default: return "Sunucuda bir sorun oluştu (\(status)). Lütfen daha sonra tekrar dene."
            }
        case .invalidResponse:
            return "Sunucudan beklenmeyen bir yanıt geldi. Lütfen daha sonra tekrar dene."
        }
    }
}

nonisolated final class GituarAPI: Sendable {
    static let shared = GituarAPI()

    static let baseURL = URL(string: "https://gituar-api.burak-kc-sp.workers.dev")!

    enum SongSort: String, Sendable {
        case new, popular, trending, title
    }

    enum Action: String, Sendable {
        case view, favorite, repertoire
    }

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 40
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    // MARK: - DTOs

    struct APISong: Decodable, Sendable {
        let id: String
        let artist: String
        let artistSlug: String?
        let title: String
        let slug: String?
        let originalKey: String?
        let status: String?
        let createdAt: Double?
        let updatedAt: Double?
        let score: Double?
        let content: String?
        let ownerId: String?
        let addedBy: String?

        var song: Song {
            Song(
                docId: id,
                artist: artist,
                songName: title,
                originalKey: originalKey ?? "",
                content: content ?? "",
                createdAt: createdAt.map { Date(timeIntervalSince1970: $0 / 1000) },
                updatedAt: updatedAt.map { Date(timeIntervalSince1970: $0 / 1000) },
                artistSlug: artistSlug,
                slug: slug,
                score: score,
                ownerId: ownerId,
                addedBy: addedBy,
                status: status,
                hasContent: content != nil
            )
        }
    }

    struct Artist: Decodable, Hashable, Sendable, Identifiable {
        let slug: String
        let name: String
        let songs: Int?
        let score: Double?
        var id: String { slug }
    }

    struct ArtistDetail: Sendable {
        let slug: String
        let name: String
        let songs: [Song]
    }

    struct SearchResults: Sendable {
        var songs: [Song] = []
        var artists: [Artist] = []
    }

    struct Me: Decodable, Sendable {
        let uid: String
        let isAdmin: Bool
    }

    private struct SongsEnvelope: Decodable { let songs: [APISong] }
    private struct SongEnvelope: Decodable { let song: APISong }
    private struct ArtistsEnvelope: Decodable { let artists: [Artist] }
    private struct ArtistDetailEnvelope: Decodable {
        struct Body: Decodable { let slug: String; let name: String; let songs: [APISong] }
        let artist: Body
    }
    private struct SearchEnvelope: Decodable { let songs: [APISong]; let artists: [Artist] }
    private struct ErrorEnvelope: Decodable { let error: String? }

    struct SongInput: Encodable, Sendable {
        var artist: String
        var title: String
        var originalKey: String
        var content: String
        /// "draft" | "pending" (admin'in "pending"i sunucuda "approved" olur)
        var status: String
        var addedBy: String?
    }

    // MARK: - Public read

    /// Engellenen kullanıcıların şarkıları listelerden çıkarılır (App Store 1.2). Liste ChordViewModel'in
    /// UserDefaults'a yazdığı "blockedUserIDs"tan okunur; kullanıcının kendi şarkıları etkilenmez.
    private func visible(_ songs: [Song]) -> [Song] {
        let blocked = Set(UserDefaults.standard.stringArray(forKey: "blockedUserIDs") ?? [])
        guard !blocked.isEmpty else { return songs }
        return songs.filter { song in
            guard let owner = song.ownerId, !owner.isEmpty else { return true }
            return !blocked.contains(owner)
        }
    }

    func songs(sort: SongSort, limit: Int = 50, offset: Int = 0) async throws -> [Song] {
        try await orOffline({
            let env: SongsEnvelope = try await get("/v1/songs", query: [
                "sort": sort.rawValue, "limit": String(min(max(limit, 1), 100)), "offset": String(max(offset, 0))
            ])
            return visible(env.songs.map(\.song))
        }, { visible(OfflineIndex.shared.songs(sort: sort, limit: limit, offset: offset)) })
    }

    /// Kimliklere göre (sırayı koruyarak) onaylı şarkılar. Silinmiş/olmayan kimlikler sessizce atlanır.
    func songs(ids: [String]) async throws -> [Song] {
        try await orOffline({ try await onlineSongs(ids: ids) }, { visible(OfflineIndex.shared.songs(ids: ids)) })
    }

    private func onlineSongs(ids: [String]) async throws -> [Song] {
        var seen = Set<String>()
        let unique = ids.filter { !$0.isEmpty && seen.insert($0).inserted }
        guard !unique.isEmpty else { return [] }
        var byId: [String: Song] = [:]
        var start = 0
        while start < unique.count {
            let chunk = unique[start..<min(start + 100, unique.count)]
            let env: SongsEnvelope = try await get("/v1/songs/batch", query: ["ids": chunk.joined(separator: ",")])
            for s in env.songs { byId[s.id] = s.song }
            start += 100
        }
        return visible(unique.compactMap { byId[$0] })
    }

    /// Tek şarkı (içerikle). Oturum varsa kimlik kartı gönderilir — sahibi/yönetici onaysız şarkıyı da görür.
    func song(id: String) async throws -> Song {
        try await orOffline({
            let env: SongEnvelope = try await get("/v1/songs/\(Self.escape(id))", authorized: .ifAvailable)
            return env.song.song
        }, { OfflineIndex.shared.song(id: id) })
    }

    func song(artistSlug: String, slug: String) async throws -> Song {
        try await orOffline({
            let env: SongEnvelope = try await get("/v1/songs/by-slug/\(Self.escape(artistSlug))/\(Self.escape(slug))")
            return env.song.song
        }, { OfflineIndex.shared.song(artistSlug: artistSlug, slug: slug) })
    }

    func artists(limit: Int = 100, offset: Int = 0) async throws -> [Artist] {
        try await orOffline({
            let env: ArtistsEnvelope = try await get("/v1/artists", query: [
                "limit": String(min(max(limit, 1), 100)), "offset": String(max(offset, 0))
            ])
            return env.artists
        }, {
            let all = OfflineIndex.shared.artists()
            return offset < all.count ? Array(all[offset..<min(all.count, offset + limit)]) : []
        })
    }

    /// Bütün sanatçılar (tek istekte, alfabetik). Popüler sanatçılar listesi bundan şarkı sayısına göre sıralanır.
    func allArtists() async throws -> [Artist] {
        try await orOffline({
            let env: ArtistsEnvelope = try await get("/v1/artists", query: ["limit": "10000"])
            return env.artists
        }, { OfflineIndex.shared.artists() })
    }

    /// Bir kullanıcının yayındaki şarkıları (kullanıcı profili).
    func songs(owner uid: String, limit: Int = 100) async throws -> [Song] {
        let env: SongsEnvelope = try await get("/v1/songs", query: ["owner": uid, "sort": "title", "limit": String(min(max(limit, 1), 100))])
        return env.songs.map(\.song)
    }

    /// Rastgele: alfabetik listenin iki rastgele yerinden 100'er şarkı alınıp karıştırılır (web'deki "Rastgele" ile aynı).
    func randomSongs(count: Int = 40, catalogSize: Int = 20000) async throws -> [Song] {
        let maxOffset = max(0, catalogSize - 100)
        let offsets = [Int.random(in: 0...maxOffset), Int.random(in: 0...maxOffset)]
        var pool: [Song] = []
        for offset in offsets { pool += try await songs(sort: .title, limit: 100, offset: offset) }
        var seen = Set<String>()
        return Array(pool.filter { seen.insert($0.docId).inserted }.shuffled().prefix(count))
    }

    /// Yeni eklenen sanatçılar: en yeni şarkılardan, sanatçının ilk görüldüğü sırayla.
    func newestArtists(limit: Int = 60) async throws -> [Artist] {
        var result: [Artist] = []
        var seen = Set<String>()
        for page in 0..<5 where result.count < limit {
            let list = try await songs(sort: .new, limit: 100, offset: page * 100)
            for song in list {
                let slug = song.resolvedArtistSlug
                if seen.insert(slug).inserted {
                    result.append(Artist(slug: slug, name: song.artist, songs: nil, score: nil))
                }
            }
            if list.count < 100 { break }
        }
        return Array(result.prefix(limit))
    }

    func artist(slug: String) async throws -> ArtistDetail {
        try await orOffline({
            let env: ArtistDetailEnvelope = try await get("/v1/artists/\(Self.escape(slug))")
            return ArtistDetail(slug: env.artist.slug, name: env.artist.name, songs: visible(env.artist.songs.map(\.song)))
        }, {
            OfflineIndex.shared.artistSongs(slug: slug).map { ArtistDetail(slug: slug, name: $0.name, songs: visible($0.songs)) }
        })
    }

    func search(_ query: String, limit: Int = 50) async throws -> SearchResults {
        try await orOffline({
            let env: SearchEnvelope = try await get("/v1/search", query: ["q": query, "limit": String(limit)])
            return SearchResults(songs: visible(env.songs.map(\.song)), artists: env.artists)
        }, {
            let r = OfflineIndex.shared.search(query, limit: limit)
            return SearchResults(songs: visible(r.songs), artists: r.artists)
        })
    }

    // MARK: - Çevrimdışı indirme

    struct CatalogVersion: Decodable, Sendable { let v: String; let max: Double; let count: Int }

    func catalogVersion() async throws -> CatalogVersion {
        try await get("/v1/version")
    }

    /// Sürüm adresli dışa aktarım sayfası (içeriklerle).
    func exportPage(version: String, limit: Int, offset: Int) async throws -> [Song] {
        let env: SongsEnvelope = try await get("/v1/export", query: ["v": version, "limit": String(limit), "offset": String(offset)])
        return env.songs.map(\.song)
    }

    /// İnternet yoksa indirilmiş kopyadan (varsa) yanıt verir.
    private func orOffline<T>(_ online: () async throws -> T, _ offline: () -> T?) async throws -> T {
        do {
            return try await online()
        } catch GituarAPIError.offline {
            if OfflineIndex.shared.isAvailable, let value = offline() { return value }
            throw GituarAPIError.offline
        }
    }

    // MARK: - Authenticated

    func me() async throws -> Me {
        try await get("/v1/me", authorized: .required)
    }

    func mySongs() async throws -> [Song] {
        let env: SongsEnvelope = try await get("/v1/me/songs", authorized: .required)
        return env.songs.map(\.song)
    }

    func createSong(_ input: SongInput) async throws -> Song {
        let env: SongEnvelope = try await send("POST", "/v1/songs", body: input)
        return env.song.song
    }

    func updateSong(id: String, _ input: SongInput) async throws -> Song {
        let env: SongEnvelope = try await send("PATCH", "/v1/songs/\(Self.escape(id))", body: input)
        return env.song.song
    }

    /// Hesap silme: kullanıcının şarkıları ve popülerlik kayıtları API'den silinir.
    func deleteMyData() async throws {
        let _: EmptyResponse = try await send("DELETE", "/v1/me", body: Optional<SongInput>.none)
    }

    func deleteSong(id: String) async throws {
        let _: EmptyResponse = try await send("DELETE", "/v1/songs/\(Self.escape(id))", body: Optional<SongInput>.none)
    }

    func pendingSongs() async throws -> [Song] {
        let env: SongsEnvelope = try await get("/v1/admin/pending", authorized: .required)
        return env.songs.map(\.song)
    }

    func setStatus(id: String, status: String) async throws {
        struct Body: Encodable { let status: String }
        let _: EmptyResponse = try await send("POST", "/v1/admin/songs/\(Self.escape(id))/status", body: Body(status: status))
    }

    // MARK: - Popularity

    /// Popülerlik kaydı — ateşle ve unut. "view" oturumsuz da gider (cihaz kimliğiyle);
    /// "favorite" / "repertoire" yalnızca oturum açıkken gönderilir.
    func track(_ action: Action, songId: String, active: Bool = true) {
        guard !songId.isEmpty else { return }
        if action != .view && Auth.auth().currentUser == nil { return }
        struct Body: Encodable {
            let songId: String
            let action: String
            let active: Bool
            let deviceId: String
        }
        let body = Body(songId: songId, action: action.rawValue, active: active, deviceId: Self.deviceId)
        Task.detached(priority: .utility) {
            do {
                let _: EmptyResponse = try await self.send("POST", "/v1/actions", body: body,
                                                           authorized: action == .view ? .ifAvailable : .required)
            } catch {
                print("⚠️ GituarAPI.track(\(action.rawValue), \(songId)): \(error.localizedDescription)")
            }
        }
    }

    /// Kalıcı, rastgele cihaz kimliği (36 karakter, [A-Za-z0-9-]).
    static var deviceId: String {
        let key = "gituarDeviceId"
        if let existing = UserDefaults.standard.string(forKey: key), existing.count >= 16 { return existing }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    // MARK: - Transport

    private enum AuthMode { case none, ifAvailable, required }
    private struct EmptyResponse: Decodable {}

    private static func escape(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? segment
    }

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:], authorized: AuthMode = .none) async throws -> T {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { throw GituarAPIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await perform(request, authorized: authorized)
    }

    private func send<T: Decodable, B: Encodable>(_ method: String, _ path: String, body: B?, authorized: AuthMode = .required) async throws -> T {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return try await perform(request, authorized: authorized)
    }

    private func perform<T: Decodable>(_ request: URLRequest, authorized: AuthMode) async throws -> T {
        var request = request
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authorized != .none {
            if let user = Auth.auth().currentUser {
                do {
                    let token = try await user.getIDToken()
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                } catch {
                    if authorized == .required { throw Self.map(error) }
                }
            } else if authorized == .required {
                throw GituarAPIError.notSignedIn
            }
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Self.map(error)
        }
        guard let http = response as? HTTPURLResponse else { throw GituarAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error
            throw GituarAPIError.server(status: http.statusCode, message: message)
        }
        if T.self == EmptyResponse.self { return EmptyResponse() as! T }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("❌ GituarAPI decode \(request.url?.path ?? ""): \(error)")
            throw GituarAPIError.invalidResponse
        }
    }

    private static func map(_ error: Error) -> Error {
        if error is GituarAPIError { return error }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
                 .timedOut, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed:
                return GituarAPIError.offline
            case .cancelled:
                return CancellationError()
            default:
                return GituarAPIError.offline
            }
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain { return GituarAPIError.offline }
        return error
    }
}
