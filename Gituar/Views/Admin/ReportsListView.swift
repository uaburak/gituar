import SwiftUI
import FirebaseFirestore

// MARK: - Report Model

struct SongReport: Identifiable {
    var id: String?
    var songId: String
    var songName: String
    var songArtist: String?
    var ownerId: String?
    var ownerUsername: String?
    var reason: String
    var reportedAt: Date?
    var status: String
    var reportedBy: String?

    /// Firestore dökümanından güvenli manuel init — Timestamp → Date dönüşümünü garantiler.
    init?(doc: QueryDocumentSnapshot) {
        let data = doc.data()
        guard let songId   = data["songId"]   as? String,
              let songName = data["songName"] as? String,
              let reason   = data["reason"]   as? String,
              let status   = data["status"]   as? String
        else { return nil }

        self.id           = doc.documentID
        self.songId       = songId
        self.songName     = songName
        self.songArtist   = data["songArtist"]   as? String
        self.ownerId      = data["ownerId"]      as? String
        self.ownerUsername = data["ownerUsername"] as? String
        self.reason       = reason
        self.status       = status
        self.reportedBy   = data["reportedBy"]   as? String
        // Firestore Timestamp → Date (FieldValue.serverTimestamp() ile yazılanlar)
        if let ts = data["reportedAt"] as? Timestamp {
            self.reportedAt = ts.dateValue()
        } else {
            self.reportedAt = nil
        }
    }
}

// MARK: - ReportsListView

struct ReportsListView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @State private var reports: [SongReport] = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var filter: ReportFilter = .pending

    private let db = Firestore.firestore()

    enum ReportFilter: String, CaseIterable, Identifiable {
        case pending   = "Bekleyen"
        case inProgress = "İşlemde"
        case dismissed = "Kapatıldı"
        var id: String { rawValue }

        /// Firestore'daki status değerleri
        var firestoreStatuses: [String] {
            switch self {
            case .pending:   return ["pending"]
            case .inProgress: return ["in_progress"]
            case .dismissed: return ["reviewed", "dismissed"]
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filtre Seçici
            Picker("Filtre", selection: $filter) {
                ForEach(ReportFilter.allCases) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            Group {
                if isLoading {
                    Spacer()
                    ProgressView("Şikayetler yükleniyor...")
                    Spacer()
                } else if let err = errorMessage {
                    // Hata mesajı — artık sessiz kalmıyor
                    Spacer()
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)
                        Text("Yüklenirken hata oluştu")
                            .font(.title3).fontWeight(.semibold)
                        Text(err)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                        Button("Tekrar Dene") {
                            Task { await fetchReports() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Spacer()
                } else if reports.isEmpty {
                    Spacer()
                    VStack(spacing: 14) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.green)
                        Text(filter == .pending ? "Bekleyen şikayet yok" : "Kayıt bulunamadı")
                            .font(.title3).fontWeight(.semibold)
                        Text("Harika! Her şey temiz görünüyor.")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(reports, id: \.id) { report in
                            ReportRow(
                                report: report,
                                filter: filter,
                                onTakeAction: { resolveReport(report, status: "in_progress") },
                                onReviewAndRemove: { removeContentAndClose(report) },
                                onDismiss: { resolveReport(report, status: "dismissed") }
                            )
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
        .navigationTitle("Şikayetler (\(reports.count))")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: filter) { await fetchReports() }
        .refreshable { await fetchReports() }
    }

    // MARK: - Firestore

    private func fetchReports() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        do {
            // ⚠️ .order(by:) + .whereField() composite index gerektirir.
            // Index yoksa query sessizce başarısız olur — bu yüzden sadece whereField kullanıp
            // sıralamayı client-side yapıyoruz.
            let snapshot = try await db.collection("reports")
                .whereField("status", in: filter.firestoreStatuses)
                .getDocuments()

            let fetched = snapshot.documents
                .compactMap { SongReport(doc: $0) }
                .sorted { ($0.reportedAt ?? .distantPast) > ($1.reportedAt ?? .distantPast) }

            print("✅ ReportsListView: \(fetched.count) şikayet yüklendi (\(filter.firestoreStatuses)). Toplam döküman: \(snapshot.documents.count)")
            await MainActor.run { self.reports = fetched }
        } catch {
            print("❌ ReportsListView fetchReports: \(error)")
            await MainActor.run { self.errorMessage = error.localizedDescription }
        }
        await MainActor.run { isLoading = false }
    }

    private func resolveReport(_ report: SongReport, status: String) {
        guard let id = report.id else { return }
        Task {
            try? await db.collection("reports").document(id).updateData(["status": status])
            await MainActor.run {
                reports.removeAll { $0.id == id }
            }
        }
    }

    /// Şarkıyı sil (user-chords'dan) ve raporu kapat.
    private func removeContentAndClose(_ report: SongReport) {
        if let song = viewModel.allSongs.first(where: { $0.id == report.songId }) {
            viewModel.deleteSong(song)
        }
        resolveReport(report, status: "reviewed")
    }
}

// MARK: - ReportRow

struct ReportRow: View {
    let report: SongReport
    let filter: ReportsListView.ReportFilter
    let onTakeAction: () -> Void
    let onReviewAndRemove: () -> Void
    let onDismiss: () -> Void
    @EnvironmentObject var viewModel: ChordViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Başlık + Sebep Etiketi
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(report.songName)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    if let artist = report.songArtist {
                        Text(artist)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text(report.reason)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(reasonColor(report.reason))
                    .clipShape(Capsule())
            }

            // Ekleyen & Tarih
            HStack(spacing: 6) {
                if let username = report.ownerUsername {
                    Label("@\(username)", systemImage: "person.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let date = report.reportedAt {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            // Aksiyon Butonları
            HStack(spacing: 10) {
                // Şarkıya git
                if let song = viewModel.allSongs.first(where: { $0.id == report.songId }) {
                    NavigationLink(destination: SongDetailView(song: song, isApprovalMode: false)) {
                        Label("Şarkıya Git", systemImage: "music.note")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.blue)
                    }
                }

                Spacer()

                if filter == .pending {
                    Button {
                        onTakeAction()
                    } label: {
                        Text("İşleme Al")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.borderless)
                } else if filter == .inProgress {
                    Button {
                        onDismiss()
                    } label: {
                        Text("Yoksay")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.borderless)

                    Button {
                        onReviewAndRemove()
                    } label: {
                        Text("İçeriği Kaldır")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.red)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.borderless)
                } else {
                    Text(report.status == "reviewed" ? "Kaldırıldı" : "Yoksayıldı")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(report.status == "reviewed" ? .red : .gray)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func reasonColor(_ reason: String) -> Color {
        switch reason {
        case "Telif Hakkı İhlali": return .purple
        case "Uygunsuz İçerik":   return .red
        case "Yanlış Akor/Söz":   return .orange
        default:                   return .gray
        }
    }
}
