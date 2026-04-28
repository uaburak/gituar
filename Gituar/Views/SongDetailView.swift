import SwiftUI

struct SongDetailView: View {
    let song: Song
    @EnvironmentObject var viewModel: ChordViewModel

    @State private var selectedKeyRoot: String = ""
    @State private var fontSize: CGFloat = 14
    @State private var showRepertoirePicker = false

    private let allNotes = ["C", "C#", "Db", "D", "D#", "Eb", "E", "F", "F#", "Gb", "G", "G#", "Ab", "A", "A#", "Bb", "B"]
    private let chromatic = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {


                // Ton Seçici
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Ton")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        // Orijinal ton + offset bilgisi
                        HStack(spacing: 4) {
                            Text("Orijinal: \(song.originalKey)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            if transposeOffset != 0 {
                                Text("\(transposeOffset > 0 ? "+" : "")\(transposeOffset)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.blue)
                            }
                        }
                        if selectedKeyRoot != getRootNote(from: song.originalKey) {
                            Button("Sıfırla") {
                                selectedKeyRoot = getRootNote(from: song.originalKey)
                            }
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                        }
                    }

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 44, maximum: 52))],
                        spacing: 7
                    ) {
                        ForEach(allNotes, id: \.self) { note in
                            Button {
                                selectedKeyRoot = note
                            } label: {
                                Text(note)
                                    .font(.system(size: 12, weight: .medium))
                                    .frame(width: 44, height: 36)
                                    .background(
                                        selectedKeyRoot == note
                                        ? Color.primary
                                        : Color(.secondarySystemBackground)
                                    )
                                    .foregroundColor(
                                        selectedKeyRoot == note
                                        ? Color(.systemBackground)
                                        : Color.primary
                                    )
                                    .cornerRadius(8)
                            }
                        }
                    }
                }

                Divider()

                // Yazı Boyutu
                HStack {
                    Text("Yazı boyutu")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                    HStack(spacing: 16) {
                        Button { fontSize = max(10, fontSize - 1) } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                        }
                        Text("\(Int(fontSize))pt")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(.secondary)
                            .frame(width: 36)
                        Button { fontSize = min(22, fontSize + 1) } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                        }
                    }
                }

                Divider()

                // ── Şarkı İçeriği (eski kodun birebir rendering'i) ──────────
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        let lines = song.content.components(separatedBy: "\n")

                        ForEach(0..<lines.count, id: \.self) { index in
                            let line = lines[index]

                            if isChordLine(line) {
                                Text(transposeLine(line, by: transposeOffset))
                                    .font(.system(size: fontSize, weight: .semibold))
                                    .tracking(-0.2)
                                    .foregroundColor(.blue)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            } else {
                                Text(line)
                                    .font(.system(size: fontSize, weight: .regular))
                                    .tracking(0)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
        .background(Color(.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                NavigationLink(destination: ArtistDetailView(artist: song.artist)) {
                    VStack(spacing: 1) {
                        Text(song.songName)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                            .foregroundColor(.primary)
                        Text(song.artist)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let impactLight = UIImpactFeedbackGenerator(style: .light)
                    impactLight.impactOccurred()
                    viewModel.toggleFavorite(song: song)
                } label: {
                    Image(systemName: viewModel.isFavorite(song: song) ? "heart.fill" : "heart")
                        .foregroundColor(viewModel.isFavorite(song: song) ? .red : .primary)
                }
            }
            
            ToolbarSpacer(.fixed, placement: .primaryAction)
            
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showRepertoirePicker = true
                } label: {
                    Image(systemName: "bookmark")
                        .foregroundColor(.primary)
                }
            }
        }
        .onAppear {
            selectedKeyRoot = getRootNote(from: song.originalKey)
            viewModel.addToRecentlyPlayed(song)
            viewModel.incrementViewCount(for: song)
        }
        .sheet(isPresented: $showRepertoirePicker) {
            RepertoirePickerSheet(song: song)
        }
    }

    // MARK: - Transpose Logic

    private var transposeOffset: Int {
        let orig = normalizeNote(getRootNote(from: song.originalKey))
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
                        Text(repertoire.name)
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "plus")
                            .foregroundColor(.secondary)
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
