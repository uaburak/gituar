import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct SongDetailView: View {
    @State private var currentSong: Song
    let playlist: [Song]?
    @EnvironmentObject var viewModel: ChordViewModel
    @Environment(\.dismiss) var dismiss

    /// Şarkı içeriğinin satırları — akor satırı tespiti şarkı değiştiğinde bir kez yapılır.
    @State private var sheetLines: [ChordTransposer.SheetLine]
    /// Ton/kapo/not durumunun hangi şarkı için yüklendiği (geri dönüşte kaydedilmemiş değişiklikleri ezmemek için).
    @State private var loadedSongId: String?
    @State private var selectedKeyRoot: String = ""
    @AppStorage("songFontSize") private var fontSize: Double = 14
    @State private var showRepertoirePicker = false
    @State private var capoFret: Int = 0
    @State private var isNoteEditing: Bool = false
    @State private var songNote: String = ""
    @State private var isFocusMode = false
    @State private var isPaused = false
    @State private var isFinished = false
    @StateObject private var autoScroller = AutoScroller()
    @AppStorage("autoScrollSpeed") private var autoScrollSpeed: Double = 14.0
    @State private var slideDirection: Edge = .trailing
    
    // Şikayet ve Engelleme State'leri
    @State private var showReportAlert = false
    @State private var showReportSuccess = false
    @State private var showReportError = false
    @State private var showBlockAlert = false
    @State private var showBlockSuccess = false
    @State private var uploaderUsername: String? = nil

    // API: şarkı içeriği ve sanatçının diğer şarkıları
    @State private var contentError: String? = nil
    @State private var isSongRemoved = false
    @State private var artistSongs: [Song] = []
    @State private var artistSongTotal: Int? = nil
    @State private var actionError: String? = nil
    @State private var isActing = false
    
    let isApprovalMode: Bool
    @ObservedObject private var adMobManager = AdMobManager.shared

    init(song: Song, playlist: [Song]? = nil, isApprovalMode: Bool = false) {
        _currentSong = State(initialValue: song)
        _sheetLines = State(initialValue: ChordTransposer.parse(song.content))
        self.playlist = playlist
        self.isApprovalMode = isApprovalMode
    }

    private var originalRoot: String {
        ChordTransposer.rootNote(of: currentSong.originalKey)
    }

    private var transposeOffset: Int {
        ChordTransposer.semitoneOffset(from: currentSong.originalKey, to: selectedKeyRoot)
    }

    // MARK: - Extracted Views (To fix compiler type-check timeout)
    
    @ViewBuilder
    private var headerControlsView: some View {
        if !isFocusMode {
            // Ton Seçici
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Ton")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    HStack(spacing: 4) {
                        Text("Orijinal: \(currentSong.originalKey)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        if transposeOffset != 0 {
                            Text("\(transposeOffset > 0 ? "+" : "")\(transposeOffset)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.blue)
                        }
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ChordTransposer.selectableKeys, id: \.self) { note in
                            Button { selectedKeyRoot = note } label: {
                                Text(note)
                                    .font(.system(size: 13, weight: .medium))
                                    .padding(.horizontal, 16).padding(.vertical, 8)
                                    .background(selectedKeyRoot == note ? Color.blue : Color(.secondarySystemBackground))
                                    .foregroundColor(selectedKeyRoot == note ? .white : .primary)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollEdgeEffectStyle(.soft)
                .padding(.horizontal, -20)
            }
            .transition(.move(edge: .top).combined(with: .opacity))

            Divider().transition(.opacity)

            // Araçlar (Kapo, Not Ekle, Yazı Boyutu)
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    // Kapo
                    Menu {
                        ForEach(0...12, id: \.self) { fret in
                            Button {
                                capoFret = fret
                            } label: {
                                Text(fret == 0 ? "Kapo Yok" : "Kapo: \(fret)")
                            }
                        }
                    } label: {
                        Text("Kapo : \(capoFret)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(Capsule())
                    }
                    
                    // Not Ekle
                    Button {
                        withAnimation {
                            isNoteEditing.toggle()
                        }
                    } label: {
                        Text(songNote.isEmpty ? "Not ekle" : "Not")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(Capsule())
                    }
                    
                    // Yazı Boyutu Stepper (Custom)
                    HStack(spacing: 0) {
                        Button { fontSize = max(10, fontSize - 1) } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                        }
                        .accessibilityLabel("Yazıyı küçült")
                        Divider().frame(height: 14)
                        Button { fontSize = min(30, fontSize + 1) } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                        }
                        .accessibilityLabel("Yazıyı büyüt")
                    }
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Capsule())
                    
                    Spacer()
                    
                    // Kaydet / Sıfırla Butonu Mantığı
                    let isModifiedFromOriginal = selectedKeyRoot != originalRoot || capoFret != 0 || !songNote.isEmpty
                    let hasSavedPreference = viewModel.songPreferences[currentSong.docId] != nil
                    
                    let isModifiedFromSaved: Bool = {
                        if let pref = viewModel.songPreferences[currentSong.docId] {
                            return selectedKeyRoot != pref.selectedKeyRoot || capoFret != pref.capoFret || songNote != pref.note
                        }
                        return false
                    }()
                    
                    if hasSavedPreference && !isModifiedFromSaved {
                        // Veri kaydedilmiş ve değişiklik yapılmamışsa "Sıfırla" butonu gösterilir
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            selectedKeyRoot = originalRoot
                            capoFret = 0
                            songNote = ""
                            isNoteEditing = false
                            viewModel.deleteSongPreference(songId: currentSong.docId)
                        } label: {
                            Text("Sıfırla")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color(.systemRed)) // Rengi istediğiniz gibi düzenleyebilirsiniz
                                .clipShape(Capsule())
                        }
                    } else {
                        // Veri yok veya değişiklik varsa "Kaydet" butonu
                        let canSave = hasSavedPreference ? isModifiedFromSaved : isModifiedFromOriginal
                        
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            viewModel.saveSongPreference(songId: currentSong.docId, key: selectedKeyRoot, capo: capoFret, note: songNote)
                        } label: {
                            Text("Kaydet")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(canSave ? .white : Color(.systemGray))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(canSave ? Color.blue : Color(.secondarySystemBackground))
                                .clipShape(Capsule())
                        }
                        .disabled(!canSave)
                    }
                }
                
                // Not Alanı
                VStack(spacing: 0) {
                    if isNoteEditing {
                        TextField("Notunuzu buraya yazın...", text: $songNote, axis: .vertical)
                            .font(.system(size: 14))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 8)
                            .transition(.opacity)
                    }
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isNoteEditing)
            .transition(.move(edge: .top).combined(with: .opacity))

            Divider().transition(.opacity)
        }
    }

    @ViewBuilder
    private var songContentView: some View {
        if viewModel.isBlocked(currentSong) {
            ContentUnavailableView(
                "İçerik gizlendi",
                systemImage: "hand.raised.fill",
                description: Text("Bu şarkı engellediğin bir kullanıcıya ait.")
            )
            .frame(minHeight: 240)
        } else if isSongRemoved {
            ContentUnavailableView(
                "Şarkı bulunamadı",
                systemImage: "music.note",
                description: Text("Bu şarkı kaldırılmış olabilir.")
            )
            .frame(minHeight: 240)
        } else if !currentSong.hasContent {
            if let contentError {
                CatalogLoadFailedView(message: contentError) {
                    Task { await loadFullContent() }
                }
                .frame(minHeight: 240)
            } else {
                CatalogLoadingView(text: "Akorlar yükleniyor…")
                    .frame(minHeight: 240)
            }
        } else {
            sheetView
        }
    }

    @ViewBuilder
    private var sheetView: some View {
        let offset = transposeOffset
        let preferFlats = ChordTransposer.prefersFlats(targetRoot: selectedKeyRoot, originalKey: currentSong.originalKey)

        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(sheetLines) { line in
                        Group {
                            if line.isChordLine {
                                Text(ChordTransposer.transpose(line.text, by: offset, preferFlats: preferFlats))
                                    .font(.system(size: fontSize, weight: .semibold))
                                    .tracking(-0.2)
                                    .foregroundColor(.blue)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            } else {
                                Text(line.text)
                                    .font(.system(size: fontSize))
                                    .foregroundColor(.primary)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                    }
                }
                .padding(.trailing, 20) // Give some space at the end of long lines
            }
            .scrollEdgeEffectStyle(.soft)
            
            // Invisible finder that hands UIScrollView to autoScroller
            ScrollViewFinder { sv in autoScroller.scrollView = sv }
                .frame(width: 0, height: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var mainScrollContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            if isApprovalMode {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Onay Bekleyen İçerik")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
            headerControlsView
            // Reklam: biri şarkının başında, biri şarkı biter bitmez. Oynatma (odak) modunda ve Pro'da hiçbiri.
            if !isFocusMode { SongAdSlot() }
            songContentView
            if !isFocusMode { SongAdSlot() }
            footerView
        }
        .padding(.horizontal, 20)
    }

    @ToolbarContentBuilder
    private var songToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            NavigationLink(destination: ArtistDetailView(song: currentSong)) {
                VStack(spacing: 1) {
                    Text(currentSong.songName).font(.system(size: 15, weight: .semibold)).lineLimit(1).foregroundColor(.primary)
                    Text(currentSong.artist).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .transaction { transaction in
                transaction.animation = nil
            }
        }
        ToolbarItem(placement: .primaryAction) {
            if isApprovalMode {
                HStack(spacing: 16) {
                    Button {
                        decide(approve: true)
                    } label: {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    }
                    .accessibilityLabel("Onayla")
                    Button {
                        decide(approve: false)
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                    }
                    .accessibilityLabel("Reddet")
                }
                .disabled(isActing)
            } else {
                Button { showRepertoirePicker = true } label: {
                    Image(systemName: viewModel.isInAnyRepertoire(currentSong) ? "bookmark.fill" : "bookmark")
                        .foregroundColor(.primary)
                }
                .accessibilityLabel("Repertuara ekle")
            }
        }

        if isFocusMode {
            ToolbarItemGroup(placement: .bottomBar) {
                Spacer()
                Menu {
                    Picker("Hız", selection: $autoScrollSpeed) {
                        Text("Çok Yavaş").tag(6.0)
                        Text("Yavaş").tag(10.0)
                        Text("Normal").tag(14.0)
                        Text("Hızlı").tag(20.0)
                        Text("Çok Hızlı").tag(28.0)
                    }
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Kaydırma hızı")
                Spacer()
                Button(isPaused ? "Devam" : "Durdur", systemImage: isPaused ? "play.fill" : "pause.fill") {
                    if isPaused {
                        if isFinished {
                            autoScroller.reset(animated: true)
                            isFinished = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                resumeScroll()
                            }
                        } else {
                            resumeScroll()
                        }
                    } else {
                        pauseScroll()
                    }
                    isPaused.toggle()
                }
                Spacer()
                Button("Kapat", systemImage: "xmark") { stopAndReset() }
                Spacer()
            }
        } else {
            ToolbarItemGroup(placement: .bottomBar) {
                if let playlist = playlist, playlist.count > 1 {
                    Button("Geri", systemImage: "chevron.left") {
                        previousSong()
                    }
                }
                Spacer()
                Button("Çal", systemImage: "play.fill") { startFocusMode() }
                Spacer()
                if let playlist = playlist, playlist.count > 1 {
                    Button("İleri", systemImage: "chevron.right") {
                        nextSong()
                    }
                }
            }
        }
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                ScrollView {
                    mainScrollContent
                        .padding(.bottom, isFocusMode ? 100 : 20)
                        .padding(.top, isFocusMode ? 200 : 20)
                }
                .scrollEdgeEffectStyle(.soft)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .id(currentSong.docId)
            .transition(.asymmetric(
                insertion: .move(edge: slideDirection == .trailing ? .trailing : .leading),
                removal: .move(edge: slideDirection == .trailing ? .leading : .trailing)
            ))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            songToolbar
        }
        .onAppear {
            // Çalarken ekran kararmasın
            ScreenAwake.retain()

            // Başka bir ekrandan (ya da tam ekran reklamdan) geri dönüldüğünde kaydedilmemiş ton/kapo/not
            // değişikliklerini ezme ve şarkı açılışını ikinci kez sayma
            if loadedSongId != currentSong.docId {
                loadStateForCurrentSong()
                // Her 4. şarkı açılışında geçiş reklamı (Pro'da hiç)
                InterstitialAdManager.shared.registerSongOpen()
            }
            autoScroller.pixelsPerSecond = CGFloat(autoScrollSpeed)
            autoScroller.onFinish = {
                isPaused = true
                isFinished = true
            }
        }
        .onChange(of: viewModel.songPreferences[currentSong.docId]) { _, newValue in
            if let pref = newValue {
                apply(pref)
            }
        }
        .onChange(of: currentSong.docId) { _, _ in
            loadStateForCurrentSong()
            InterstitialAdManager.shared.registerSongOpen()
            
            autoScroller.scrollView = nil
            autoScroller.reset()
            
            isPaused = false
            isFinished = false
        }
        .onChange(of: autoScrollSpeed) { _, newValue in
            autoScroller.pixelsPerSecond = CGFloat(newValue)
        }
        .onDisappear {
            ScreenAwake.release()
            autoScroller.reset()
            // Odak modundayken başka ekrana geçildiyse dönüşte "Devam" ile sürdürülebilsin
            if isFocusMode { isPaused = true }
        }
        .sheet(isPresented: $showRepertoirePicker) {
            RepertoirePickerSheet(song: currentSong)
        }
        .alert("İçeriği Şikayet Et", isPresented: $showReportAlert) {
            Button("Uygunsuz İçerik", role: .destructive) { reportContent("Uygunsuz İçerik") }
            Button("Telif Hakkı İhlali", role: .destructive) { reportContent("Telif Hakkı İhlali") }
            Button("Yanlış Akor/Söz", role: .destructive) { reportContent("Yanlış Akor/Söz") }
            Button("İptal", role: .cancel) { }
        } message: {
            Text("Bu içeriği neden şikayet etmek istiyorsunuz? İnceleme ekibimiz en kısa sürede kontrol edecektir.")
        }
        .alert("Şikayet Alındı", isPresented: $showReportSuccess) {
            Button("Tamam", role: .cancel) { }
        } message: {
            Text("Bildiriminiz için teşekkürler. İçerik en kısa sürede inceleme ekibimiz tarafından kontrol edilecektir.")
        }
        .alert("Şikayet Gönderilemedi", isPresented: $showReportError) {
            Button("Tamam", role: .cancel) { }
        } message: {
            Text("Şikayet gönderilirken bir hata oluştu. İnternet bağlantınızı kontrol edip tekrar deneyin.")
        }
        .alert("Kullanıcıyı Engelle", isPresented: $showBlockAlert) {
            Button("Evet, Engelle", role: .destructive) { blockUser() }
            Button("İptal", role: .cancel) { }
        } message: {
            Text("Bu kullanıcıyı engellemek istediğinize emin misiniz? Engellediğiniz kullanıcıların içeriklerini görmeyeceksiniz.")
        }
        .alert("Kullanıcı Engellendi", isPresented: $showBlockSuccess) {
            Button("Tamam", role: .cancel) { }
        } message: {
            Text("Kullanıcı başarıyla engellendi.")
        }
        .alert("İşlem Başarısız", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("Tamam", role: .cancel) { }
        } message: {
            Text(actionError ?? "")
        }
        .task(id: currentSong.docId) {
            await loadFullContent()
            async let artistLoad: Void = loadArtistSongs()
            await loadUploader()
            await artistLoad
        }
    }

    // MARK: - API

    /// Listeden gelen (içeriksiz) şarkının sözlerini/akorlarını çeker.
    private func loadFullContent() async {
        let songId = currentSong.docId
        contentError = nil
        isSongRemoved = false
        do {
            let full = try await viewModel.fullSong(for: currentSong)
            guard currentSong.docId == songId else { return }
            if !currentSong.hasContent || full.content != currentSong.content || full.ownerId != currentSong.ownerId {
                let previousKey = currentSong.originalKey
                currentSong = full
                sheetLines = ChordTransposer.parse(full.content)
                // Ton bilgisi olmadan açılan (ör. şikayetten) şarkıda seçili tonu orijinale çek
                if previousKey != full.originalKey && viewModel.songPreferences[songId] == nil {
                    selectedKeyRoot = originalRoot
                }
            }
        } catch let error as GituarAPIError where error.isNotFound {
            guard currentSong.docId == songId else { return }
            isSongRemoved = true
        } catch is CancellationError {
        } catch {
            guard currentSong.docId == songId else { return }
            contentError = error.localizedDescription
        }
    }

    private func loadArtistSongs() async {
        let slug = currentSong.resolvedArtistSlug
        do {
            let detail = try await viewModel.artistDetail(slug: slug)
            artistSongTotal = detail.songs.count
            artistSongs = Array(detail.songs.filter { $0.docId != currentSong.docId }.prefix(5))
        } catch {
            artistSongTotal = nil
            artistSongs = []
        }
    }

    private func decide(approve: Bool) {
        guard !isActing else { return }
        isActing = true
        let song = currentSong
        Task {
            defer { isActing = false }
            do {
                if approve {
                    try await viewModel.approveSong(song)
                } else {
                    try await viewModel.rejectSong(song)
                }
                dismiss()
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private func loadUploader() async {
        do {
            if let ownerId = currentSong.ownerId, !ownerId.isEmpty {
                do {
                    let profile = try await UserService.shared.getPublicUserProfile(uid: ownerId)
                    await MainActor.run {
                        if let username = profile?.username {
                            self.uploaderUsername = username
                        } else {
                            self.uploaderUsername = currentSong.addedBy
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.uploaderUsername = currentSong.addedBy
                    }
                }
            } else {
                self.uploaderUsername = currentSong.addedBy
            }
        }
    }

    // MARK: - Song State

    /// Geçerli şarkı için kayıtlı ton/kapo/not tercihini yükler; yoksa orijinal tona döner.
    private func loadStateForCurrentSong() {
        loadedSongId = currentSong.docId
        viewModel.fetchSongPreference(for: currentSong.docId)

        if let pref = viewModel.songPreferences[currentSong.docId] {
            apply(pref)
        } else {
            selectedKeyRoot = originalRoot
            capoFret = 0
            songNote = ""
            isNoteEditing = false
        }

        if !isApprovalMode {
            viewModel.addToRecentlyPlayed(currentSong)
            // Popülerlik: şarkı açıldı
            viewModel.trackView(currentSong)
        }
    }

    private func apply(_ pref: UserSongPreference) {
        selectedKeyRoot = pref.selectedKeyRoot
        capoFret = pref.capoFret
        songNote = pref.note
        // Kayıtlı not varsa gizli kalmasın
        if !pref.note.isEmpty { isNoteEditing = true }
    }

    // MARK: - Actions (Report & Block)
    
    private func reportContent(_ reason: String) {
        let db = Firestore.firestore()
        Task {
            var data: [String: Any] = [
                "songId": currentSong.id,
                "songName": currentSong.songName,
                "songArtist": currentSong.artist,
                "reason": reason,
                "reportedAt": FieldValue.serverTimestamp(),
                "status": "pending"
            ]
            if let ownerId = currentSong.ownerId { data["ownerId"] = ownerId }
            if let username = uploaderUsername { data["ownerUsername"] = username }
            if let reporterId = Auth.auth().currentUser?.uid { data["reportedBy"] = reporterId }
            do {
                try await db.collection("reports").addDocument(data: data)
                print("✅ reportContent: Firestore'a yazıldı — \(currentSong.id) / \(reason)")
                await MainActor.run { showReportSuccess = true }
            } catch {
                print("❌ reportContent: \(error)")
                await MainActor.run { showReportError = true }
            }
        }
    }

    private func blockUser() {
        guard let ownerId = currentSong.ownerId, !ownerId.isEmpty else { return }
        viewModel.blockUser(ownerId: ownerId)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showBlockSuccess = true
        }
    }

    // MARK: - Navigation Control
    private func nextSong() {
        guard let playlist = playlist,
              let currentIndex = playlist.firstIndex(where: { $0.id == currentSong.id }) else { return }
        let nextIndex = (currentIndex + 1) % playlist.count
        show(playlist[nextIndex], slidingFrom: .trailing)
    }

    private func previousSong() {
        guard let playlist = playlist,
              let currentIndex = playlist.firstIndex(where: { $0.id == currentSong.id }) else { return }
        let prevIndex = (currentIndex - 1 + playlist.count) % playlist.count
        show(playlist[prevIndex], slidingFrom: .leading)
    }

    private func show(_ song: Song, slidingFrom edge: Edge) {
        slideDirection = edge
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let lines = ChordTransposer.parse(song.content)
        withAnimation(.interpolatingSpring(stiffness: 300, damping: 30)) {
            currentSong = song
            sheetLines = lines
        }
    }

    // MARK: - Auto Scroll Control

    private func startFocusMode() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isPaused = false
        isFinished = false
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { isFocusMode = true }
        // Wait for layout to settle + ScrollViewFinder's 0.3s delay before starting
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { autoScroller.start() }
    }

    private func pauseScroll() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        autoScroller.pause()
    }

    private func resumeScroll() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        autoScroller.start()
    }

    private func stopAndReset() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        autoScroller.reset()
        isPaused = false
        isFinished = false
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { isFocusMode = false }
    }

    @ViewBuilder
    private var footerView: some View {
        if !isFocusMode {
            VStack(alignment: .leading, spacing: 20) {
                Divider().padding(.top, 40)

                // UGC Added By Notice & Legal Text
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        if let uploader = uploaderUsername, !uploader.isEmpty {
                            Text("@\(uploader)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                        } else {
                            Text("@anonim")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        
                        Spacer()
                        
                        // Kendi şarkısında "Engelle" gösterme (kullanıcı kendini engelleyebiliyordu)
                        if let ownerId = currentSong.ownerId, !ownerId.isEmpty, ownerId != viewModel.currentUserId {
                            Button {
                                showBlockAlert = true
                            } label: {
                                Text("Engelle")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.red)
                            }
                            
                            Divider()
                                .frame(height: 12)
                        }
                        
                        Button {
                            showReportAlert = true
                        } label: {
                            Text("Şikayet Et")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.red)
                        }
                    }
                    
                    Text("⚠️ Gituar, kullanıcıların kendi içeriklerini paylaştığı bir topluluk platformudur. Tüm içerikler kullanıcı sorumluluğundadır.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    NavigationLink(destination: LegalContactView()) {
                        Text("\(Text("Bu içerik müzik eğitimi amacı ile yayımlanmış olup hakları kendi sahiplerine aittir. Telif ihlali içerdiğini düşünüyorsanız bizimle ").foregroundColor(.secondary))\(Text("iletişime").foregroundColor(.blue).underline())\(Text(" geçebilirsiniz.").foregroundColor(.secondary))")
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                }
                .padding(.bottom, 8)

                Divider()

                // Artist Section (Styled like AllArtistsView list item)
                NavigationLink(destination: ArtistDetailView(song: currentSong)) {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.secondarySystemBackground))
                                .frame(width: 42, height: 42)
                            Text(currentSong.artist.prefix(1).uppercased())
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(currentSong.artist)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Text(artistSongTotal.map { "\($0) Şarkı" } ?? "Tüm şarkılar")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(.systemGray4))
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())

                // Other Songs List
                if !artistSongs.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(artistSongs, id: \.docId) { otherSong in
                            Divider()
                            
                            NavigationLink(destination: SongDetailView(song: otherSong)) {
                                HStack(spacing: 0) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(otherSong.songName)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        Text(otherSong.originalKey)
                                            .font(.system(size: 13))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(Color(.systemGray4))
                                }
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Repertoire Picker
struct RepertoirePickerSheet: View {
    let song: Song
    @EnvironmentObject var viewModel: ChordViewModel
    @Environment(\.dismiss) var dismiss

    @State private var showingNewRepertoire = false
    @State private var newRepertoireName = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List(viewModel.repertoires) { repertoire in
                    let alreadyAdded = repertoire.songIds.contains(song.id)
                    Button {
                        viewModel.addSong(song, to: repertoire)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(repertoire.name)
                                    .foregroundColor(.primary)
                                Text("\(repertoire.songIds.count) Şarkı")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if alreadyAdded {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "plus")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .disabled(alreadyAdded)
                }
                .listStyle(.plain)
                .scrollEdgeEffectStyle(.soft)

                // Alt - Yeni Repertuar Oluştur Butonu
                Button {
                    showingNewRepertoire = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Yeni Repertuar Oluştur")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color(.systemBackground))
            }
            .navigationTitle("Repertuara Ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Kapat") { dismiss() }
                }
            }
            .alert("Yeni Repertuar", isPresented: $showingNewRepertoire) {
                TextField("İsim", text: $newRepertoireName)
                Button("İptal", role: .cancel) { newRepertoireName = "" }
                Button("Oluştur") {
                    if !newRepertoireName.trimmingCharacters(in: .whitespaces).isEmpty {
                        viewModel.addRepertoire(name: newRepertoireName)
                        newRepertoireName = ""
                    }
                }
            }
        }
    }
}
