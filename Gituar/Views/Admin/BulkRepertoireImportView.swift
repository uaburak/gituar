import SwiftUI
import UniformTypeIdentifiers

struct BulkRepertoireImportView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var showFilePicker = false
    @State private var parsedEntries: [ChordViewModel.BulkRepertoireEntry] = []
    @State private var parseError: String? = nil
    @State private var phase: Phase = .idle

    @State private var progress: Int = 0
    @State private var total: Int = 0
    @State private var resultSuccess: Int = 0
    @State private var resultFailed: Int = 0
    @State private var unresolved: [String] = []

    enum Phase { case idle, preview, importing, done }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .idle:      idleView
                case .preview:   previewView
                case .importing: importingView
                case .done:      doneView
                }
            }
            .navigationTitle("Toplu Repertuar Yükle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if phase != .importing {
                        Button("Kapat") { dismiss() }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if phase == .preview {
                        Button("Yükle") { startImport() }
                            .fontWeight(.semibold)
                    }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [UTType.json],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
        }
    }

    // MARK: - Idle (Dosya Seç)

    private var idleView: some View {
        List {
            // İllüstrasyon Section
            Section {
                VStack(spacing: 20) {
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(.tint)
                        .padding(.top, 24)

                    VStack(spacing: 6) {
                        Text("Toplu Repertuar Yükle")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("JSON dosyandaki her kategori,\nFirestore'a otomatik eklenir.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        parseError = nil
                        showFilePicker = true
                    } label: {
                        Label("JSON Dosyası Seç", systemImage: "folder.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
            }

            if let error = parseError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            // Format açıklaması
            Section("Beklenen Format") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("""
[\n  {\n    \"name\": \"Başlangıç için\",\n    \"songs\": [\"Ahmet Kaya - Ağladıkça\", \"sezen-aksu/sen-agla\"]\n  },\n  {\n    \"name\": \"Hareketli Şarkılar\",\n    \"songIds\": [\"im251107c025\"]\n  }\n]\n\nŞarkı: API kimliği, \"sanatçı-slug/şarkı-slug\" ya da \"Sanatçı - Şarkı\". Bulunamayanlar sonuçta listelenir.
""")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.insetGrouped)
        .scrollEdgeEffectStyle(.soft)
    }

    // MARK: - Preview

    private var previewView: some View {
        List {
            // Özet
            Section {
                HStack {
                    Label {
                        Text("\(parsedEntries.count) Repertuar")
                            .fontWeight(.medium)
                    } icon: {
                        Image(systemName: "square.stack.3d.up.fill")
                            .foregroundStyle(.tint)
                    }

                    Spacer()

                    Label {
                        Text("\(parsedEntries.reduce(0) { $0 + $1.songIds.count }) Şarkı")
                            .fontWeight(.medium)
                    } icon: {
                        Image(systemName: "music.note")
                            .foregroundStyle(.green)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Yüklenecekler")
            } footer: {
                Text("\"Yükle\" butonuna basınca tüm repertuarlar Firestore'a yazılır.")
            }

            // Liste
            Section("Repertuarlar") {
                ForEach(Array(parsedEntries.enumerated()), id: \.offset) { index, entry in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .trailing)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name)
                                .font(.system(size: 15, weight: .medium))
                            Text("\(entry.songIds.count) şarkı")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 18))
                    }
                    .padding(.vertical, 2)
                }
            }

            // Farklı dosya seç
            Section {
                Button(role: .destructive) {
                    withAnimation { phase = .idle }
                } label: {
                    Label("Farklı Dosya Seç", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollEdgeEffectStyle(.soft)
    }

    // MARK: - Importing

    private var importingView: some View {
        VStack(spacing: 32) {
            Spacer()

            ProgressView(value: total > 0 ? Double(progress) / Double(total) : 0)
                .progressViewStyle(.circular)
                .scaleEffect(2.5)
                .tint(.accentColor)
                .padding(.bottom, 8)

            VStack(spacing: 6) {
                Text("Yükleniyor…")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("\(progress) / \(total) repertuar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.default, value: progress)
            }

            Text("Lütfen uygulamayı kapatmayın.")
                .font(.footnote)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .padding()
    }

    // MARK: - Done

    private var doneView: some View {
        List {
            Section {
                VStack(spacing: 20) {
                    Image(systemName: resultFailed == 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(resultFailed == 0 ? .green : .orange)
                        .padding(.top, 24)

                    VStack(spacing: 6) {
                        Text(resultFailed == 0 ? "Yükleme Tamamlandı" : "Kısmen Tamamlandı")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Öne Çıkanlar bölümünde görünecek.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
            }

            Section {
                HStack {
                    Label("Başarılı", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                    Spacer()
                    Text("\(resultSuccess)")
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                        .monospacedDigit()
                }

                if resultFailed > 0 {
                    HStack {
                        Label("Hatalı", systemImage: "xmark.circle")
                            .foregroundStyle(.red)
                        Spacer()
                        Text("\(resultFailed)")
                            .fontWeight(.semibold)
                            .foregroundStyle(.red)
                            .monospacedDigit()
                    }
                }
            } header: {
                Text("Sonuç")
            }

            if !unresolved.isEmpty {
                Section {
                    ForEach(unresolved, id: \.self) { item in
                        Text(item).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Bulunamayan şarkılar (\(unresolved.count))")
                } footer: {
                    Text("Bu şarkılar repertuara eklenmedi. Kimliği ya da \"Sanatçı - Şarkı\" yazımını kontrol et.")
                }
            }

            Section {
                Button {
                    dismiss()
                } label: {
                    Text("Tamam")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .fontWeight(.semibold)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollEdgeEffectStyle(.soft)
    }

    // MARK: - Logic

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            parseError = "Dosya açılamadı: \(error.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }
            parseJSONFile(at: url)
        }
    }

    private func parseJSONFile(at url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            parseError = "Dosyaya erişim izni alınamadı."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: url)
            let entries = try JSONDecoder().decode([ChordViewModel.BulkRepertoireEntry].self, from: data)

            guard !entries.isEmpty else {
                parseError = "JSON dosyası boş veya geçersiz format."
                return
            }

            parsedEntries = entries
            parseError = nil
            withAnimation { phase = .preview }
        } catch {
            parseError = "Geçersiz JSON: \(error.localizedDescription)"
        }
    }

    private func startImport() {
        total = parsedEntries.count
        progress = 0

        withAnimation { phase = .importing }

        Task {
            do {
                let (success, failed, missing) = try await viewModel.bulkImportRepertoires(
                    entries: parsedEntries
                ) { current, _ in
                    progress = current
                }
                await MainActor.run {
                    resultSuccess = success
                    resultFailed = failed
                    unresolved = missing
                    withAnimation { phase = .done }
                }
            } catch {
                await MainActor.run {
                    resultSuccess = 0
                    resultFailed = total
                    withAnimation { phase = .done }
                }
            }
        }
    }
}
