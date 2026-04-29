import SwiftUI

struct SongDetailView: View {
    @State private var currentSong: Song
    let playlist: [Song]?
    @EnvironmentObject var viewModel: ChordViewModel

    @State private var selectedKeyRoot: String = ""
    @State private var fontSize: CGFloat = 14
    @State private var showRepertoirePicker = false
    @State private var isFocusMode = false
    @State private var isPaused = false
    @State private var isFinished = false
    @StateObject private var autoScroller = AutoScroller()
    @AppStorage("autoScrollSpeed") private var autoScrollSpeed: Double = 14.0
    @State private var slideDirection: Edge = .trailing

    init(song: Song, playlist: [Song]? = nil) {
        _currentSong = State(initialValue: song)
        self.playlist = playlist
    }

    private let allNotes = ["C", "C#", "Db", "D", "D#", "Eb", "E", "F", "F#", "Gb", "G", "G#", "Ab", "A", "A#", "Bb", "B"]
    private let chromatic = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    private var songLines: [String] {
        currentSong.content.components(separatedBy: "\n")
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                ScrollView {
                    ZStack {
                VStack(alignment: .leading, spacing: 24) {
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
                            if selectedKeyRoot != getRootNote(from: currentSong.originalKey) {
                                Button("Sıfırla") { selectedKeyRoot = getRootNote(from: currentSong.originalKey) }
                                    .font(.system(size: 13))
                                    .foregroundColor(.primary)
                            }
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(allNotes, id: \.self) { note in
                                    Button { selectedKeyRoot = note } label: {
                                        Text(note)
                                            .font(.system(size: 13, weight: .medium))
                                            .padding(.horizontal, 16).padding(.vertical, 8)
                                            .background(selectedKeyRoot == note ? Color.primary : Color(.secondarySystemBackground))
                                            .foregroundColor(selectedKeyRoot == note ? Color(.systemBackground) : Color.primary)
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

                    // Yazı Boyutu
                    HStack {
                        HStack(spacing: 8) {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                viewModel.toggleFavorite(song: currentSong)
                            } label: {
                                Image(systemName: viewModel.isFavorite(song: currentSong) ? "heart.fill" : "heart")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(viewModel.isFavorite(song: currentSong) ? .red : .primary)
                                    .frame(width: 30, height: 30)
                                    .background(.regularMaterial)
                                    .clipShape(Circle())
                                    .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)
                            }
                            
                            Text("Yazı boyutu")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 16) {
                            Button { fontSize = max(10, fontSize - 1) } label: {
                                Image(systemName: "minus").font(.system(size: 14)).foregroundColor(.primary)
                            }
                            Text("\(Int(fontSize))pt").font(.system(size: 13, design: .rounded)).foregroundColor(.secondary).frame(width: 36)
                            Button { fontSize = min(22, fontSize + 1) } label: {
                                Image(systemName: "plus").font(.system(size: 14)).foregroundColor(.primary)
                            }
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))

                    Divider().transition(.opacity)
                }

                // Song Content
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

                footerView
                }
                .background(Color(.systemBackground))
                .padding(.horizontal, 20)
            }
            // Add extra bottom padding in focus mode so the auto scroller can scroll past the text slightly
            .padding(.bottom, isFocusMode ? 100 : 20)
            .padding(.top, isFocusMode ? 200 : 20)
        }
        .frame(width: geo.size.width, height: geo.size.height)
        .id(currentSong.docId)
        .transition(.asymmetric(
            insertion: .move(edge: slideDirection == .trailing ? .trailing : .leading),
            removal: .move(edge: slideDirection == .trailing ? .leading : .trailing)
        ))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
                Button { showRepertoirePicker = true } label: {
                    Image(systemName: "bookmark").foregroundColor(.primary)
                }
            }

            // MARK: Bottom Bar
            if isFocusMode {
                ToolbarItem(placement: .bottomBar) { Spacer() }
                
                ToolbarItem(placement: .bottomBar) {
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
                }

                ToolbarSpacer(.fixed, placement: .bottomBar)
                
                ToolbarItem(placement: .bottomBar) {
                    Button(isPaused ? "Devam" : "Durdur", systemImage: isPaused ? "play.fill" : "pause.fill") {
                        if isPaused {
                            if isFinished {
                                autoScroller.reset(animated: true)
                                isFinished = false
                                // Süreyi 0.8'e çıkardık ki en başa kayma animasyonu tamamen bitsin
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
                }
                
                ToolbarSpacer(.fixed, placement: .bottomBar)

                ToolbarItem(placement: .bottomBar) {
                    Button("Kapat", systemImage: "xmark") { stopAndReset() }
                }
                
                ToolbarItem(placement: .bottomBar) { Spacer() }
                
            } else {
                if let playlist = playlist, playlist.count > 1 {
                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            previousSong()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 20, weight: .medium))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                    }
                }
                
                ToolbarItem(placement: .bottomBar) { Spacer() }
                
                ToolbarItem(placement: .bottomBar) {
                    Button("Çal", systemImage: "play.fill") { startFocusMode() }
                }
                
                ToolbarItem(placement: .bottomBar) { Spacer() }
                
                if let playlist = playlist, playlist.count > 1 {
                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            nextSong()
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 20, weight: .medium))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                    }
                }
            }
        }
        .onAppear {
            if selectedKeyRoot.isEmpty {
                selectedKeyRoot = getRootNote(from: currentSong.originalKey)
            }
            viewModel.addToRecentlyPlayed(currentSong)
            viewModel.incrementViewCount(for: currentSong)
            autoScroller.pixelsPerSecond = CGFloat(autoScrollSpeed)
            autoScroller.onFinish = {
                isPaused = true
                isFinished = true
            }
        }
        .onChange(of: currentSong.docId) { _, _ in
            selectedKeyRoot = getRootNote(from: currentSong.originalKey)
            viewModel.addToRecentlyPlayed(currentSong)
            viewModel.incrementViewCount(for: currentSong)
            
            // Giden ekranın scroll pozisyonunun sıfırlanmasını engellemek için
            // eski ScrollView ile olan bağı koparıyoruz.
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
    }

    // MARK: - Navigation Control
    private func nextSong() {
        guard let playlist = playlist,
              let currentIndex = playlist.firstIndex(where: { ($0.id ?? $0.docId) == (currentSong.id ?? currentSong.docId) }) else { return }
        let nextIndex = (currentIndex + 1) % playlist.count
        slideDirection = .trailing
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.interpolatingSpring(stiffness: 300, damping: 30)) {
            currentSong = playlist[nextIndex]
        }
    }

    private func previousSong() {
        guard let playlist = playlist,
              let currentIndex = playlist.firstIndex(where: { ($0.id ?? $0.docId) == (currentSong.id ?? currentSong.docId) }) else { return }
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

                // Copyright Disclaimer
                NavigationLink(destination: LegalContactView()) {
                    Text("Bu içerik müzik eğitimi amacı ile yayımlanmış olup hakları kendi sahiplerine aittir. Telif ihlali içerdiğini düşünüyorsanız bizimle ")
                        .foregroundColor(.secondary)
                    + Text("iletişime")
                        .foregroundColor(.blue)
                        .underline()
                    + Text(" geçebilirsiniz.")
                        .foregroundColor(.secondary)
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)

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
                let allArtistSongs = viewModel.songsForArtist(currentSong.artist).filter { ($0.id ?? $0.docId) != (currentSong.id ?? currentSong.docId) }
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

    var body: some View {
        NavigationStack {
            List(viewModel.repertoires) { repertoire in
                Button {
                    viewModel.addSong(song, to: repertoire)
                    dismiss()
                } label: {
                    HStack {
                        Text(repertoire.name).foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "plus").foregroundColor(.secondary)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Repertuara Ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }
}
