import SwiftUI
import FirebaseFirestore
import FirebaseAuth

/// Yönetim · Pro üyeler (web'deki yönetim panelinin "Pro üyeler" bölümüyle aynı veri):
/// hediye Pro verme (kullanıcı adıyla, süreli/süresiz), geri alma; App Store abonelerini listeleme.
/// Veri: users/{uid}.proGrant (yalnızca yönetici yazar) ve users/{uid}.pro (uygulamanın yazdığı abonelik).
struct ProMembersView: View {
    struct Member: Identifiable {
        let id: String
        let username: String
        let giftActive: Bool
        let giftUntil: Date?
        let giftNote: String?
        let subActive: Bool
        let subUntil: Date?

        var isPro: Bool {
            let valid = { (active: Bool, until: Date?) in active && (until == nil || until! > Date()) }
            return valid(giftActive, giftUntil) || valid(subActive, subUntil)
        }
    }

    private let db = Firestore.firestore()
    @State private var members: [Member] = []
    @State private var isLoading = true
    @State private var loadError: String?

    @State private var username = ""
    @State private var months = 1
    @State private var note = ""
    @State private var message: String?
    @State private var isSaving = false
    @State private var revokeTarget: Member?

    var body: some View {
        List {
            Section {
                TextField("Kullanıcı adı (@ olmadan)", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Picker("Süre", selection: $months) {
                    Text("1 ay").tag(1)
                    Text("3 ay").tag(3)
                    Text("6 ay").tag(6)
                    Text("1 yıl").tag(12)
                    Text("Süresiz").tag(0)
                }
                TextField("Not (isteğe bağlı)", text: $note)
                Button {
                    Task { await grant() }
                } label: {
                    if isSaving { ProgressView() } else { Text("Hediye Pro Ver") }
                }
                .disabled(isSaving || username.trimmingCharacters(in: .whitespaces).isEmpty)
                if let message {
                    Text(message).font(.footnote).foregroundColor(.secondary)
                }
            } header: {
                Text("Hediye Pro")
            } footer: {
                Text("Süre hâlâ devam eden hediyenin üstüne eklenir. Pro olan kullanıcıya uygulamada ve sitede reklam gösterilmez.")
            }

            Section {
                if isLoading && members.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if let loadError, members.isEmpty {
                    Text(loadError).foregroundColor(.secondary)
                } else if members.isEmpty {
                    Text("Pro üye yok.").foregroundColor(.secondary)
                } else {
                    ForEach(members) { m in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("@\(m.username.isEmpty ? "?" : m.username)").font(.system(size: 15, weight: .semibold))
                                if !m.isPro {
                                    Text("· süresi dolmuş").font(.system(size: 13)).foregroundColor(.secondary)
                                }
                            }
                            Text(detail(m)).font(.system(size: 12)).foregroundColor(.secondary)
                        }
                        .swipeActions {
                            if m.giftActive {
                                Button("Geri Al", role: .destructive) { revokeTarget = m }
                            }
                        }
                    }
                }
            } header: {
                Text("Pro üyeler\(members.isEmpty ? "" : " · \(members.filter(\.isPro).count) aktif")")
            } footer: {
                Text("Hediye Pro'yu geri almak için satırı sola kaydır. App Store aboneliğine dokunulmaz.")
            }
        }
        .navigationTitle("Pro Üyeler")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .alert("Hediye Pro geri alınsın mı?", isPresented: Binding(get: { revokeTarget != nil }, set: { if !$0 { revokeTarget = nil } })) {
            Button("Geri Al", role: .destructive) {
                if let m = revokeTarget { Task { await revoke(m) } }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text(revokeTarget.map { "@\($0.username) kullanıcısının hediye Pro'su kaldırılacak." } ?? "")
        }
    }

    private func detail(_ m: Member) -> String {
        let until = { (d: Date?) in d.map { $0.formatted(date: .abbreviated, time: .omitted) + "'e kadar" } ?? "süresiz" }
        var parts: [String] = []
        if m.giftActive { parts.append("Hediye · \(until(m.giftUntil))\(m.giftNote.map { $0.isEmpty ? "" : " · \($0)" } ?? "")") }
        if m.subActive { parts.append("App Store · \(until(m.subUntil))") }
        return parts.joined(separator: " · ")
    }

    private static func member(_ id: String, _ x: [String: Any]) -> Member {
        let g = x["proGrant"] as? [String: Any]
        let p = x["pro"] as? [String: Any]
        return Member(
            id: id,
            username: x["username"] as? String ?? "",
            giftActive: g?["active"] as? Bool ?? false,
            giftUntil: (g?["until"] as? Timestamp)?.dateValue(),
            giftNote: g?["note"] as? String,
            subActive: p?["active"] as? Bool ?? false,
            subUntil: (p?["until"] as? Timestamp)?.dateValue()
        )
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let gifts = db.collection("users").whereField("proGrant.active", isEqualTo: true).getDocuments()
            async let subs = db.collection("users").whereField("pro.active", isEqualTo: true).getDocuments()
            var map: [String: Member] = [:]
            for d in try await gifts.documents + subs.documents { map[d.documentID] = Self.member(d.documentID, d.data()) }
            members = map.values.sorted { $0.username.isOrderedBeforeInTurkish($1.username) }
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func grant() async {
        let name = username.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "")
            .lowercased(with: Locale(identifier: "tr-TR"))
        guard !name.isEmpty, let adminUid = Auth.auth().currentUser?.uid else { return }
        isSaving = true
        defer { isSaving = false }
        message = "Aranıyor…"
        do {
            let snap = try await db.collection("users").whereField("username", isEqualTo: name).limit(to: 1).getDocuments()
            guard let doc = snap.documents.first else {
                message = "@\(name) adında kullanıcı bulunamadı."
                return
            }
            let current = Self.member(doc.documentID, doc.data())
            var until: Date?
            if months > 0 {
                let base = current.giftActive && (current.giftUntil ?? .distantPast) > Date() ? current.giftUntil! : Date()
                until = Calendar.current.date(byAdding: .month, value: months, to: base)
            }
            try await db.collection("users").document(doc.documentID).updateData([
                "proGrant": [
                    "active": true,
                    "until": until.map { Timestamp(date: $0) } ?? NSNull(),
                    "note": note.trimmingCharacters(in: .whitespaces),
                    "by": adminUid,
                    "at": Timestamp(date: Date()),
                ] as [String: Any]
            ])
            message = "@\(current.username) artık Pro (\(until.map { $0.formatted(date: .abbreviated, time: .omitted) + "'e kadar" } ?? "süresiz"))."
            username = ""
            note = ""
            await load()
        } catch {
            message = "Kaydedilemedi: \(error.localizedDescription)"
        }
    }

    private func revoke(_ m: Member) async {
        do {
            try await db.collection("users").document(m.id).updateData(["proGrant": FieldValue.delete()])
            await load()
        } catch {
            message = "Geri alınamadı: \(error.localizedDescription)"
        }
    }
}
