import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct SongDetailView: View {
    @State private var currentSong: Song
    let playlist: [Song]?
    @EnvironmentObject var viewModel: ChordViewModel
    @Environment(\.dismiss) var dismiss

    @State private var selectedKeyRoot: String = ""
    @State private var fontSize: CGFloat = 14
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
    
    let isApprovalMode: Bool

    init(song: Song, playlist: [Song]? = nil, isApprovalMode: Bool = false) {
        _currentSong = State(initialValue: song)
        self.playlist = playlist
        self.isApprovalMode = isApprovalMode
    }

    private let allNotes = ["C", "C#", "Db", "D", "D#", "Eb", "E", "F", "F#", "Gb", "G", "G#", "Ab", "A", "A#", "Bb", "B"]
    private let chromatic = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    private var songLines: [String] {
        currentSong.content.components(separatedBy: "\n")
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
                        ForEach(allNotes, id: \.self) { note in
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
                        Text("Not ekle")
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
                        Divider().frame(height: 14)
                        Button { fontSize = min(30, fontSize + 1) } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                        }
                    }
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Capsule())
                    
                    Spacer()
                    
                    // Kaydet / Sıfırla Butonu Mantığı
                    let isModifiedFromOriginal = selectedKeyRoot != getRootNote(from: currentSong.originalKey) || capoFret != 0 || !songNote.isEmpty
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
                            selectedKeyRoot = getRootNote(from: currentSong.originalKey)
                            capoFret = 0
                            songNote = ""
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
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(songLines.enumerated()), id: \.offset) { index, line in
                        Group {
                            if isChordLine(line) {
                                Text(transposeLine(line, by: transposeOffset))
                                    .font(.system(size: fontSize, weight: .semibold))
                                    .tracking(-0.2)
                                    .foregroundColor(.blue)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            } else {
                                Text(line)
                                    .font(.system(size: fontSize))
                                    .foregroundColor(.primary)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                    }
                }
                .padding(.trailing, 20) // Give some space at the end of long lines
            }
            
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
            songContentView
            footerView
        }
        .padding(.horizontal, 20)
    }

    @ToolbarContentBuilder
    private var songToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            NavigationLink(destination: ArtistDetailView(artist: currentSong.artist)) {
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
                        viewModel.approveSong(currentSong)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    }
                    Button {
                        viewModel.rejectSong(currentSong)
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                    }
                }
            } else {
                Button { showRepertoirePicker = true } label: {
                    Image(systemName: "bookmark").foregroundColor(.primary)
                }
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
            viewModel.fetchSongPreference(for: currentSong.docId)
            
            if let pref = viewModel.songPreferences[currentSong.docId] {
                selectedKeyRoot = pref.selectedKeyRoot
                capoFret = pref.capoFret
                songNote = pref.note
            } else if selectedKeyRoot.isEmpty {
                selectedKeyRoot = getRootNote(from: currentSong.originalKey)
            }
            
            if !isApprovalMode {
                viewModel.addToRecentlyPlayed(currentSong)
                viewModel.incrementViewCount(for: currentSong)
            }
            autoScroller.pixelsPerSecond = CGFloat(autoScrollSpeed)
            autoScroller.onFinish = {
                isPaused = true
                isFinished = true
            }
        }
        .onChange(of: viewModel.songPreferences[currentSong.docId]) { _, newValue in
            if let pref = newValue {
                selectedKeyRoot = pref.selectedKeyRoot
                capoFret = pref.capoFret
                songNote = pref.note
            }
        }
        .onChange(of: currentSong.docId) { _, _ in
            viewModel.fetchSongPreference(for: currentSong.docId)
            
            if let pref = viewModel.songPreferences[currentSong.docId] {
                selectedKeyRoot = pref.selectedKeyRoot
                capoFret = pref.capoFret
                songNote = pref.note
            } else {
                selectedKeyRoot = getRootNote(from: currentSong.originalKey)
                capoFret = 0
                songNote = ""
                isNoteEditing = false
            }
            
            if !isApprovalMode {
                viewModel.addToRecentlyPlayed(currentSong)
                viewModel.incrementViewCount(for: currentSong)
            }
            
            autoScroller.scrollView = nil
            autoScroller.reset()
            
            isPaused = false
            isFinished = false
        }
        .onChange(of: autoScrollSpeed) { _, newValue in
            autoScroller.pixelsPerSecond = CGFloat(newValue)
        }
        .onDisappear { autoScroller.reset() }
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
        .task(id: currentSong.docId) {
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
                await MainActor.run {
                    self.uploaderUsername = currentSong.addedBy
                }
            }
        }
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
        slideDirection = .trailing
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.interpolatingSpring(stiffness: 300, damping: 30)) {
            currentSong = playlist[nextIndex]
        }
    }

    private func previousSong() {
        guard let playlist = playlist,
              let currentIndex = playlist.firstIndex(where: { $0.id == currentSong.id }) else { return }
        let prevIndex = (currentIndex - 1 + playlist.count) % playlist.count
        slideDirection = .leading
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.interpolatingSpring(stiffness: 300, damping: 30)) {
            currentSong = playlist[prevIndex]
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

                // Ad Banner
                let bannerWidth = ((UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.width ?? 320) - 40
                AdBannerView(viewWidth: bannerWidth)
                .padding(.bottom, 8)

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
                        
                        if let ownerId = currentSong.ownerId, !ownerId.isEmpty {
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
                NavigationLink(destination: ArtistDetailView(artist: currentSong.artist)) {
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
                            Text("\(viewModel.songsForArtist(currentSong.artist).count) Şarkı")
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
                let allArtistSongs = viewModel.songsForArtist(currentSong.artist).filter { $0.id != currentSong.id }
                let artistSongs: [Song] = {
                    if allArtistSongs.contains(where: { $0.popularityScore > 0 }) {
                        return Array(allArtistSongs.sorted { $0.popularityScore > $1.popularityScore }.prefix(5))
                    } else {
                        return Array(allArtistSongs.shuffled().prefix(5))
                    }
                }()
                
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

    // MARK: - Transpose Logic

    private var transposeOffset: Int {
        let orig = normalizeNote(getRootNote(from: currentSong.originalKey))
        let sel  = normalizeNote(selectedKeyRoot)
        guard let oi = chromatic.firstIndex(of: orig),
              let si = chromatic.firstIndex(of: sel) else { return 0 }
        return si - oi
    }

    private func getRootNote(from key: String) -> String {
        let regex = try? NSRegularExpression(pattern: "^([A-G][b#]?)")
        let ns = key as NSString
        if let m = regex?.firstMatch(in: key, range: NSRange(location: 0, length: ns.length)) {
            return ns.substring(with: m.range)
        }
        return "C"
    }

    private func transposeLine(_ line: String, by offset: Int) -> String {
        guard offset != 0 else { return line }
        var result = ""; var word = ""
        for ch in line {
            if ch.isWhitespace {
                if !word.isEmpty { result += transposeChord(word, by: offset); word = "" }
                result.append(ch)
            } else { word.append(ch) }
        }
        if !word.isEmpty { result += transposeChord(word, by: offset) }
        return result
    }

    private func transposeChord(_ chord: String, by offset: Int) -> String {
        let regex = try? NSRegularExpression(pattern: "^([A-G][b#]?)(.*)$")
        let range = NSRange(location: 0, length: chord.utf16.count)
        guard let m = regex?.firstMatch(in: chord, range: range),
              let rr = Range(m.range(at: 1), in: chord),
              let sr = Range(m.range(at: 2), in: chord) else { return chord }
        let root   = normalizeNote(String(chord[rr]))
        let suffix = String(chord[sr])
        guard let idx = chromatic.firstIndex(of: root) else { return chord }
        return chromatic[(idx + offset + 12) % 12] + suffix
    }

    private func normalizeNote(_ n: String) -> String {
        ["Db": "C#", "Eb": "D#", "Gb": "F#", "Ab": "G#", "Bb": "A#"][n] ?? n
    }

    private func isChordLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return false }
        let words = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let pat   = "^[A-G][b#]?(m|maj|min|dim|aug|sus|add|7|9|M|\\+|[0-9])*$"
        let count = words.filter { $0.range(of: pat, options: .regularExpression) != nil }.count
        return trimmed.lowercased().hasPrefix("x") ||
               trimmed.lowercased().contains("intro") ||
               (Double(count) / Double(words.count) >= 0.5)
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
