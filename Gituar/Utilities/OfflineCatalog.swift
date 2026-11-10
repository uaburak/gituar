import Foundation
import SwiftUI
import Combine

// MARK: - OfflineCatalog
//
// "Tümünü indir": yayındaki bütün şarkılar (içerikleriyle) cihaza indirilir. İnternet yokken GituarAPI
// şarkı, sanatçı, arama ve listeleri bu kopyadan verir. Dosya: Application Support/offline-catalog.json
// İndirme API'nin sürüm adresli dışa aktarımıyla yapılır (/v1/version + /v1/export?v=…): aynı sürüm Cloudflare
// önbelleğinden gelir; sürüm değişince ayarlarda "Güncelle" görünür.

/// Diskteki kayıt (Song'un kalıcı hâli).
nonisolated struct OfflineSongRecord: Codable, Sendable {
    let id: String
    let artist: String
    let artistSlug: String?
    let title: String
    let slug: String?
    let originalKey: String
    let content: String
    let createdAt: Double?
    let updatedAt: Double?
    let score: Double?
    let ownerId: String?
    let addedBy: String?

    init(_ s: Song) {
        id = s.docId; artist = s.artist; artistSlug = s.artistSlug; title = s.songName; slug = s.slug
        originalKey = s.originalKey; content = s.content
        createdAt = s.createdAt.map { $0.timeIntervalSince1970 * 1000 }
        updatedAt = s.updatedAt.map { $0.timeIntervalSince1970 * 1000 }
        score = s.score; ownerId = s.ownerId; addedBy = s.addedBy
    }

    var song: Song {
        Song(docId: id, artist: artist, songName: title, originalKey: originalKey, content: content,
             createdAt: createdAt.map { Date(timeIntervalSince1970: $0 / 1000) },
             updatedAt: updatedAt.map { Date(timeIntervalSince1970: $0 / 1000) },
             artistSlug: artistSlug, slug: slug, score: score, ownerId: ownerId, addedBy: addedBy,
             status: "approved", hasContent: true)
    }
}

nonisolated struct OfflineFile: Codable, Sendable {
    let version: String
    let savedAt: Double
    let songs: [OfflineSongRecord]
}

/// İndirilmiş kopyanın bellekteki dizini. GituarAPI (her iş parçacığından) okur; kilitle korunur.
nonisolated final class OfflineIndex: @unchecked Sendable {
    static let shared = OfflineIndex()

    private let lock = NSLock()
    private var songs: [Song] = []
    private var byId: [String: Song] = [:]
    private var bySlug: [String: Song] = [:]
    private(set) var version: String?
    /// Çevrimdışı erişim Pro'ya özel: ProManager Pro durumuna göre açar/kapatır
    private var enabled = false

    var isAvailable: Bool { lock.withLock { enabled && !songs.isEmpty } }

    func setEnabled(_ on: Bool) { lock.withLock { enabled = on } }

    func replace(with file: OfflineFile?) {
        let list = file?.songs.map(\.song) ?? []
        lock.withLock {
            songs = list
            byId = Dictionary(list.map { ($0.docId, $0) }, uniquingKeysWith: { a, _ in a })
            bySlug = Dictionary(list.compactMap { s in s.slug.map { ("\(s.resolvedArtistSlug)/\($0)", s) } }, uniquingKeysWith: { a, _ in a })
            version = file?.version
        }
    }

    func song(id: String) -> Song? { lock.withLock { byId[id] } }
    func song(artistSlug: String, slug: String) -> Song? { lock.withLock { bySlug["\(artistSlug)/\(slug)"] } }
    func songs(ids: [String]) -> [Song] { lock.withLock { ids.compactMap { byId[$0] } } }

    func all() -> [Song] { lock.withLock { songs } }

    func songs(sort: GituarAPI.SongSort, limit: Int, offset: Int) -> [Song] {
        let list = all()
        let sorted: [Song]
        switch sort {
        case .new: sorted = list.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        case .popular, .trending: sorted = list.sorted { ($0.score ?? 0) > ($1.score ?? 0) }
        case .title: sorted = list.sorted { $0.songName.isOrderedBeforeInTurkish($1.songName) }
        }
        guard offset < sorted.count else { return [] }
        return Array(sorted[offset..<min(sorted.count, offset + limit)])
    }

    func artistSongs(slug: String) -> (name: String, songs: [Song])? {
        let list = all().filter { $0.resolvedArtistSlug == slug }
        guard let first = list.first else { return nil }
        return (first.artist, list.sorted { $0.songName.isOrderedBeforeInTurkish($1.songName) })
    }

    func artists() -> [GituarAPI.Artist] {
        var map: [String: (name: String, count: Int, score: Double)] = [:]
        for s in all() {
            let slug = s.resolvedArtistSlug
            let cur = map[slug] ?? (s.artist, 0, 0)
            map[slug] = (cur.name, cur.count + 1, cur.score + (s.score ?? 0))
        }
        return map.map { GituarAPI.Artist(slug: $0.key, name: $0.value.name, songs: $0.value.count, score: $0.value.score) }
            .sorted { $0.name.isOrderedBeforeInTurkish($1.name) }
    }

    func search(_ query: String, limit: Int) -> GituarAPI.SearchResults {
        let found = Array(SongSearch.filter(all(), query: query, ranked: true).prefix(limit))
        let q = query.turkeyNormalized
        let artists = artists().filter { $0.name.turkeyNormalized.contains(q) }.prefix(5)
        return GituarAPI.SearchResults(songs: found, artists: Array(artists))
    }
}

// MARK: - İndirme durumu (ayarlar ve ekrandaki ilerleme bildirimi)

@MainActor
final class OfflineStore: ObservableObject {
    static let shared = OfflineStore()

    enum State: Equatable {
        case idle
        case downloading(done: Int, total: Int)
        case finished(count: Int)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var savedCount = 0
    @Published private(set) var savedBytes: Int64 = 0
    @Published private(set) var savedAt: Date?
    @Published private(set) var savedVersion: String?
    /// Sunucudaki sürüm indirilenden farklı (yeni/düzenlenen şarkı var)
    @Published private(set) var updateAvailable = false

    private var task: Task<Void, Never>?

    nonisolated private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("offline-catalog.json")
    }

    var isDownloading: Bool { if case .downloading = state { return true } else { return false } }

    private init() {
        // Diskteki kopya arka planda belleğe alınır
        Task.detached(priority: .utility) {
            let url = OfflineStore.fileURL
            guard let data = try? Data(contentsOf: url),
                  let file = try? JSONDecoder().decode(OfflineFile.self, from: data) else { return }
            OfflineIndex.shared.replace(with: file)
            await MainActor.run {
                OfflineStore.shared.savedCount = file.songs.count
                OfflineStore.shared.savedBytes = Int64(data.count)
                OfflineStore.shared.savedAt = Date(timeIntervalSince1970: file.savedAt / 1000)
                OfflineStore.shared.savedVersion = file.version
            }
        }
    }

    /// Uygulama açılışında çağrılır (dosyayı yükletir).
    func start() {}

    /// Sunucu sürümünü sorar; indirilen kopya eskiyse "Güncelle" görünür.
    func checkForUpdate() async {
        guard let saved = savedVersion, saved != "partial", !isDownloading else { return }
        if let v = try? await GituarAPI.shared.catalogVersion() {
            updateAvailable = v.v != saved
        }
    }

    func download() {
        guard !isDownloading, ProManager.shared.isPro else { return }
        state = .downloading(done: 0, total: 0)
        task = Task {
            do {
                let version = try await GituarAPI.shared.catalogVersion()
                state = .downloading(done: 0, total: version.count)
                var records: [OfflineSongRecord] = []
                records.reserveCapacity(version.count)
                let page = 1000
                var offset = 0
                while true {
                    try Task.checkCancellation()
                    let songs = try await GituarAPI.shared.exportPage(version: version.v, limit: page, offset: offset)
                    records += songs.map(OfflineSongRecord.init)
                    state = .downloading(done: records.count, total: max(version.count, records.count))
                    if songs.count < page { break }
                    offset += page
                }
                let file = OfflineFile(version: version.v, savedAt: Date().timeIntervalSince1970 * 1000, songs: records)
                let data = try await Task.detached(priority: .utility) { () throws -> Data in
                    let data = try JSONEncoder().encode(file)
                    try data.write(to: OfflineStore.fileURL, options: .atomic)
                    return data
                }.value
                OfflineIndex.shared.replace(with: file)
                savedCount = records.count
                savedBytes = Int64(data.count)
                savedAt = Date()
                savedVersion = version.v
                updateAvailable = false
                state = .finished(count: records.count)
                try? await Task.sleep(for: .seconds(2.5))
                if case .finished = state { state = .idle }
            } catch is CancellationError {
                state = .idle
            } catch {
                state = .failed(error.localizedDescription)
                try? await Task.sleep(for: .seconds(4))
                if case .failed = state { state = .idle }
            }
        }
    }

    /// Bütün katalog mu indirildi? (Seçmeli indirmede sürüm "partial" yazılır.)
    var hasFullCatalog: Bool { savedVersion != nil && savedVersion != "partial" }

    /// Seçilen şarkıları (repertuar, editör seçimleri, kendi şarkıları) içerikleriyle indirip mevcut kopyaya ekler.
    /// `ready`: içeriği zaten elde olan şarkılar (ör. kendi şarkıların) ağa gitmeden eklenir.
    func download(songIds: [String], ready: [Song] = []) {
        guard !isDownloading, ProManager.shared.isPro else { return }
        let have = Set(OfflineIndex.shared.all().map(\.docId))
        let readyIds = Set(ready.map(\.docId))
        var seen = Set<String>()
        let ids = songIds.filter { !have.contains($0) && !readyIds.contains($0) && seen.insert($0).inserted }
        let fresh = ready.filter { $0.hasContent && !have.contains($0.docId) }
        let total = ids.count + fresh.count
        guard total > 0 else {
            state = .finished(count: 0)
            Task { try? await Task.sleep(for: .seconds(2)); if case .finished = state { state = .idle } }
            return
        }
        state = .downloading(done: 0, total: total)
        task = Task {
            do {
                var fetched: [Song] = fresh
                state = .downloading(done: fetched.count, total: total)
                // Altışar şarkı aynı anda
                for chunk in stride(from: 0, to: ids.count, by: 6).map({ Array(ids[$0..<min($0 + 6, ids.count)]) }) {
                    try Task.checkCancellation()
                    let got = await withTaskGroup(of: Song?.self) { group -> [Song] in
                        for id in chunk { group.addTask { try? await GituarAPI.shared.song(id: id) } }
                        var out: [Song] = []
                        for await song in group { if let song, song.hasContent { out.append(song) } }
                        return out
                    }
                    fetched += got
                    state = .downloading(done: min(total, fetched.count), total: total)
                }
                var byId = Dictionary(OfflineIndex.shared.all().map { ($0.docId, $0) }, uniquingKeysWith: { a, _ in a })
                for song in fetched { byId[song.docId] = song }
                let version = savedVersion ?? "partial"
                let file = OfflineFile(version: version, savedAt: Date().timeIntervalSince1970 * 1000,
                                       songs: byId.values.map(OfflineSongRecord.init))
                let data = try await Task.detached(priority: .utility) { () throws -> Data in
                    let data = try JSONEncoder().encode(file)
                    try data.write(to: OfflineStore.fileURL, options: .atomic)
                    return data
                }.value
                OfflineIndex.shared.replace(with: file)
                savedCount = file.songs.count
                savedBytes = Int64(data.count)
                savedAt = Date()
                savedVersion = version
                state = .finished(count: fetched.count)
                try? await Task.sleep(for: .seconds(2.5))
                if case .finished = state { state = .idle }
            } catch is CancellationError {
                state = .idle
            } catch {
                state = .failed(error.localizedDescription)
                try? await Task.sleep(for: .seconds(4))
                if case .failed = state { state = .idle }
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        state = .idle
    }

    func delete() {
        cancel()
        try? FileManager.default.removeItem(at: Self.fileURL)
        OfflineIndex.shared.replace(with: nil)
        savedCount = 0
        savedBytes = 0
        savedAt = nil
        savedVersion = nil
        updateAvailable = false
    }
}

// MARK: - Ekranda kalan ilerleme bildirimi

/// İndirme sürerken her ekranın üstünde duran bildirim (bitince kısa bir "İndirildi" gösterip kaybolur).
struct OfflineDownloadToast: View {
    @ObservedObject private var store = OfflineStore.shared

    var body: some View {
        Group {
            switch store.state {
            case .idle:
                EmptyView()
            case .downloading(let done, let total):
                toast {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Şarkılar indiriliyor")
                                .font(.system(size: 14, weight: .semibold))
                            Text(total > 0 ? "Bitince internetsiz de açılır" : "Hazırlanıyor…")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        Spacer()
                        Text(total > 0 ? "%\(Int(Double(done) / Double(total) * 100))" : "")
                            .font(.system(size: 15, weight: .bold))
                            .monospacedDigit()
                    }
                    ProgressView(value: total > 0 ? Double(done) / Double(total) : 0)
                        .tint(.blue)
                }
            case .finished:
                toast {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("İndirildi · şarkılar internetsiz de açılır")
                    }
                    .font(.system(size: 14, weight: .semibold))
                }
            case .failed(let message):
                toast {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("İndirilemedi: \(message)").lineLimit(2)
                    }
                    .font(.system(size: 13, weight: .medium))
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.state)
    }

    private func toast<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(14)
            .frame(maxWidth: 420)
            .glassEffect(in: .rect(cornerRadius: 20))
            .padding(.horizontal, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .combine)
    }
}

/// Ayarlardaki "Çevrimdışı" bölümü.
struct OfflineSettingsSection: View {
    @EnvironmentObject private var viewModel: ChordViewModel
    @ObservedObject private var store = OfflineStore.shared
    @ObservedObject private var pro = ProManager.shared
    @State private var confirmDelete = false
    @State private var showProPrompt = false
    @State private var openPro = false

    private var repertoireIds: [String] { viewModel.repertoires.flatMap(\.songIds) }
    private var editorIds: [String] { viewModel.editorRepertoires.flatMap(\.songIds) }

    /// Listedeki şarkılardan kaçı cihazda (savedCount değişince yeniden hesaplanır)
    private func saved(_ ids: [String]) -> Int {
        _ = store.savedCount
        let set = Set(ids)
        return OfflineIndex.shared.songs(ids: Array(set)).count
    }

    var body: some View {
        Group {
            Section {
                row("Repertuarlarımdaki Şarkılar", icon: "music.mic", ids: repertoireIds) {
                    store.download(songIds: repertoireIds)
                }
                row("Editörün Seçimleri", icon: "star", ids: editorIds) {
                    store.download(songIds: editorIds)
                }
                if !viewModel.mySongs.isEmpty {
                    row("Şarkılarım", icon: "music.quarternote.3", ids: viewModel.mySongs.map(\.docId)) {
                        store.download(songIds: [], ready: viewModel.mySongs)
                    }
                }
                Button {
                    if pro.isPro { store.download() } else { showProPrompt = true }
                } label: {
                    HStack {
                        Label { Text("Tüm Şarkılar").foregroundColor(.primary) } icon: { Image(systemName: "icloud.and.arrow.down") }
                        Spacer()
                        if store.hasFullCatalog {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        } else if !pro.isPro {
                            proBadge
                        }
                    }
                }
                .disabled(store.isDownloading || store.hasFullCatalog)
            }

            if store.savedCount > 0 || store.isDownloading {
                Section {
                    if store.savedCount > 0 {
                        HStack {
                            Label("Cihazda", systemImage: "internaldrive")
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: store.savedBytes, countStyle: .file))
                                .foregroundColor(.secondary)
                        }
                    }
                    if store.hasFullCatalog && store.updateAvailable && pro.isPro {
                        Button {
                            store.download()
                        } label: {
                            Label("Güncelle", systemImage: "arrow.clockwise")
                        }
                        .disabled(store.isDownloading)
                    }
                    if store.isDownloading {
                        Button("İndirmeyi Durdur", role: .cancel) { store.cancel() }
                    }
                    if store.savedCount > 0 {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label("İndirilenleri Sil", systemImage: "trash")
                                .foregroundColor(.red)
                        }
                        .disabled(store.isDownloading)
                    }
                }
            }
        }
        .task { if pro.isPro { await store.checkForUpdate() } }
        .alert("Gituar Pro gerekli", isPresented: $showProPrompt) {
            Button("Pro'ya Geç") { openPro = true }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Şarkıları indirip internetsiz çalmak Gituar Pro'ya özel. Pro ile reklamlar da kalkar.")
        }
        .navigationDestination(isPresented: $openPro) { ProView() }
        .alert("İndirilenler silinsin mi?", isPresented: $confirmDelete) {
            Button("Sil", role: .destructive) { store.delete() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Cihazdaki şarkı kopyası silinir. İnternet varken şarkılar yine açılır.")
        }
    }

    private var proBadge: some View {
        Text("PRO")
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.accentColor, in: Capsule())
    }

    /// Seçmeli indirme satırı: kaçı cihazda / hepsi indiyse tik.
    @ViewBuilder
    private func row(_ title: String, icon: String, ids: [String], action: @escaping () -> Void) -> some View {
        let unique = Set(ids).count
        let have = saved(ids)
        Button {
            if pro.isPro { action() } else { showProPrompt = true }
        } label: {
            HStack {
                Label { Text(title).foregroundColor(.primary) } icon: { Image(systemName: icon) }
                Spacer()
                if !pro.isPro {
                    proBadge
                } else if unique > 0 && have >= unique {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                } else {
                    Text(unique == 0 ? "Şarkı yok" : "\(have)/\(unique)")
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .disabled(store.isDownloading || (pro.isPro && (unique == 0 || have >= unique)))
    }
}
