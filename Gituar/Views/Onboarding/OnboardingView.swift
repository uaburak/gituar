import SwiftUI

// MARK: - Ortak arka plan (giriş + tanıtım)

/// Yumuşak, hareketsiz renk geçişi: üstte mavi-mor ışık, aşağıda sayfa rengi.
struct GituarBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let bg = Color(.systemBackground)
        MeshGradient(
            width: 3, height: 3,
            points: [[0, 0], [0.5, 0], [1, 0],
                     [0, 0.45], [0.55, 0.4], [1, 0.5],
                     [0, 1], [0.5, 1], [1, 1]],
            colors: [
                Color.accentColor.opacity(scheme == .dark ? 0.55 : 0.35), Color.purple.opacity(scheme == .dark ? 0.45 : 0.25), Color.pink.opacity(scheme == .dark ? 0.35 : 0.2),
                Color.accentColor.opacity(0.12), Color.purple.opacity(0.08), Color.orange.opacity(0.08),
                bg, bg, bg,
            ]
        )
        .ignoresSafeArea()
    }
}

// MARK: - Tanıtım

/// İlk açılışta bir kez: beş kısa adım, her biri özelliğin canlı küçük bir örneğiyle.
struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") var hasSeenOnboarding: Bool = false
    @Environment(\.dismiss) var dismiss
    @State private var step = 0

    private struct Step {
        let title: String
        let text: String
    }

    private let steps: [Step] = [
        Step(title: "Gituar'a hoş geldin", text: "Topluluğun paylaştığı akorlar, senin repertuarın. Hepsi tek yerde."),
        Step(title: "Ara, bul, çal", text: "Şarkı ya da sanatçı adının birkaç harfini yaz; aradığın akor saniyeler içinde önünde."),
        Step(title: "Akora dokun, duy", text: "Kâğıttaki her akora dokununca şeması açılır ve gitarda nasıl tınladığını duyarsın."),
        Step(title: "Ton sesine uysun", text: "Tek dokunuşla transpoze et, kapo tak. Akorlar anında değişir."),
        Step(title: "Ellerin gitarda kalsın", text: "Otomatik kaydırma şarkıyı senin hızında akıtır. Yazıyı büyüt, akorları gizle, ekran kararmasın."),
        Step(title: "Repertuarını kur", text: "Sahne, kamp ateşi, pratik… Şarkıları listelere ekle, istersen herkesle paylaş."),
        Step(title: "Kendi şarkını ekle", text: "Bildiğin akorları yaz, onaydan sonra herkes çalsın. Taslakların yalnızca sende kalır."),
        Step(title: "Paylaş, keşfet", text: "Şarkıyı ya da repertuarını tek linkle gönder. Diğer gitaristlerin profillerine göz at."),
        Step(title: "İnternetsiz de çal", text: "Gituar Pro ile bütün şarkıları cihazına indir; çekmeyen yerde bile çal. Reklamlar da kalkar."),
    ]

    private var isLast: Bool { step == steps.count - 1 }

    var body: some View {
        ZStack {
            GituarBackdrop()

            VStack(spacing: 0) {
                // Atla
                HStack {
                    Spacer()
                    if !isLast {
                        Button("Atla") { finish() }
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .glassEffect(in: .capsule)
                    }
                }
                .frame(height: 44)
                .padding(.horizontal, 20)

                TabView(selection: $step) {
                    ForEach(steps.indices, id: \.self) { i in
                        page(i).tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Alt: nokta göstergesi + buton
                VStack(spacing: 28) {
                    HStack(spacing: 8) {
                        ForEach(steps.indices, id: \.self) { i in
                            Capsule()
                                .fill(i == step ? Color.primary : Color.primary.opacity(0.18))
                                .frame(width: i == step ? 22 : 7, height: 7)
                        }
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: step)

                    Button {
                        if isLast { finish() } else { withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { step += 1 } }
                    } label: {
                        Text(isLast ? "Başla" : "Devam")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.accentColor, in: Capsule())
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder
    private func page(_ i: Int) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            Group {
                switch i {
                case 0: WelcomeDemo()
                case 1: SearchDemo(active: step == 1)
                case 2: ChordTapDemo(active: step == 2)
                case 3: TransposeDemo(active: step == 3)
                case 4: AutoScrollDemo(active: step == 4)
                case 5: RepertoireDemo(active: step == 5)
                case 6: AddSongDemo(active: step == 6)
                case 7: ShareDemo(active: step == 7)
                default: OfflineDemo(active: step == 8)
                }
            }
            .frame(height: 340)
            Spacer(minLength: 24)
            VStack(spacing: 12) {
                Text(steps[i].title)
                    .font(.system(size: 30, weight: .bold))
                    .multilineTextAlignment(.center)
                Text(steps[i].text)
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
            Spacer(minLength: 16)
        }
    }

    private func finish() {
        hasSeenOnboarding = true
        dismiss()
    }
}

// MARK: - Canlı örnekler (uygulamadaki ekranların sade kopyaları)

private let bg2 = Color(.secondarySystemBackground)

/// Uygulamadaki şarkı satırı (SongRowCard ile aynı ölçüler).
private struct DemoSongRow: View {
    let title: String, artist: String, key: String
    var body: some View {
        HStack(spacing: 14) {
            Text(String(title.prefix(1)).uppercased(with: Locale(identifier: "tr")))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .frame(width: 48, height: 48)
                .background(bg2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(artist).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(key).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
    }
}

/// Akor kâğıdı satırı: mavi akor satırı + söz.
private struct DemoSheetLine: View {
    let chords: String, lyric: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(chords).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.accentColor)
            Text(lyric).font(.system(size: 15))
        }
    }
}

private struct WelcomeDemo: View {
    @State private var appear = false
    var body: some View {
        VStack(spacing: 18) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
                .scaleEffect(appear ? 1 : 0.85)
                .opacity(appear ? 1 : 0)
            Text("Gituar")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) { appear = true } }
    }
}

/// Ana sayfadaki alt arama çubuğu + sonuç listesi.
private struct SearchDemo: View {
    let active: Bool
    private let query = "sezen"
    private let results = [("Sen Ağla", "Bm"), ("Ah İstanbul", "Gm"), ("Affet", "G#m")]
    @State private var typed = 0
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if typed >= 3 {
                    Text("Şarkılar").font(.system(size: 17, weight: .bold)).padding(.bottom, 4)
                }
                ForEach(results.indices, id: \.self) { i in
                    if typed >= 3 + i {
                        DemoSongRow(title: results[i].0, artist: "Sezen Aksu", key: results[i].1)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        Divider().padding(.leading, 62)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: 260, alignment: .top)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                Text(typed == 0 ? "Şarkı veya sanatçı ara..." : String(query.prefix(typed)))
                    .foregroundStyle(typed == 0 ? .secondary : .primary)
                Spacer()
            }
            .font(.system(size: 17))
            .padding(.horizontal, 16)
            .frame(height: 48)
            .glassEffect(in: .capsule)
        }
        .padding(.horizontal, 24)
        .onChange(of: active, initial: true) { _, on in
            timer?.invalidate()
            guard on else { typed = 0; return }
            typed = 0
            timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { t in
                Task { @MainActor in
                    if typed < query.count { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { typed += 1 } } else { t.invalidate() }
                }
            }
        }
        .onDisappear { timer?.invalidate() }
    }
}

/// Akor kâğıdı + uygulamanın kendi akor kartı (ChordPopupCard).
private struct ChordTapDemo: View {
    let active: Bool
    private let chords = ["Am", "F", "C", "G"]
    @State private var current = 0
    @State private var timer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 0) {
                    ForEach(chords.indices, id: \.self) { i in
                        Text(chords[i])
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 4)
                            .background(i == current ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 5))
                            .frame(width: 70, alignment: .leading)
                    }
                }
                Text("Gece iner yavaş yavaş şehre").font(.system(size: 15))
            }
            .padding(.horizontal, 4)
            ChordPopupCard(chord: chords[current], capo: 0, onClose: {})
                .id(current)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 24)
        .onChange(of: active, initial: true) { _, on in
            timer?.invalidate()
            guard on else { return }
            timer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: true) { _ in
                Task { @MainActor in withAnimation(.easeInOut(duration: 0.25)) { current = (current + 1) % chords.count } }
            }
        }
        .onDisappear { timer?.invalidate() }
    }
}

/// Şarkı sayfasındaki ton şeridi ve araç satırı; akorlar seçilen tona göre değişir.
private struct TransposeDemo: View {
    let active: Bool
    private let keys = ["A", "A#", "B", "C", "C#", "D"]
    private let lines = ["Am       F        C       G", "A#m      F#       C#      G#", "Bm       G        D       A",
                         "Cm       G#       D#      A#", "C#m      A        E       B", "Dm       A#       F       C"]
    @State private var k = 0
    @State private var timer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Ton").foregroundStyle(.secondary)
                Spacer()
                Text("Orijinal: Am").foregroundStyle(.secondary)
            }
            .font(.system(size: 13))
            HStack(spacing: 8) {
                ForEach(keys.indices, id: \.self) { i in
                    Text(keys[i])
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(i == k ? .white : .primary)
                        .frame(minWidth: 44, minHeight: 34)
                        .background(i == k ? Color.accentColor : bg2, in: Capsule())
                }
            }
            Divider()
            HStack(spacing: 8) {
                Text("Kapo : 0").padding(.horizontal, 14).frame(height: 34).background(bg2, in: Capsule())
                Text("Not ekle").padding(.horizontal, 14).frame(height: 34).background(bg2, in: Capsule())
                HStack(spacing: 14) { Image(systemName: "minus"); Image(systemName: "plus") }
                    .padding(.horizontal, 14).frame(height: 34).background(bg2, in: Capsule())
            }
            .font(.system(size: 13, weight: .medium))
            Divider()
            DemoSheetLine(chords: lines[k], lyric: "Gece iner yavaş yavaş şehre")
                .contentTransition(.opacity)
        }
        .padding(.horizontal, 24)
        .onChange(of: active, initial: true) { _, on in
            timer?.invalidate()
            guard on else { k = 0; return }
            timer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: true) { _ in
                Task { @MainActor in withAnimation(.snappy) { k = (k + 1) % keys.count } }
            }
        }
        .onDisappear { timer?.invalidate() }
    }
}

/// Kâğıt kendi kendine akar; altta şarkı sayfasının oynatıcı düğmeleri.
private struct AutoScrollDemo: View {
    let active: Bool
    @State private var offset: CGFloat = 0
    private let lines: [(String, String)] = [
        ("Am        F", "Sabah olur pencereden"), ("C         G", "Bir ışık düşer odama"),
        ("Am        F", "Kahvemi koyar beklerim"), ("C      G", "Yolun düşer mi buraya"),
        ("Dm       Am", "Şehir uyanır yavaşça"), ("F         E", "Ben hâlâ aynı yerdeyim"),
        ("Am        F", "Sabah olur pencereden"), ("C         G", "Bir ışık düşer odama"),
        ("Am        F", "Kahvemi koyar beklerim"), ("C      G", "Yolun düşer mi buraya"),
    ]

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(lines.indices, id: \.self) { i in DemoSheetLine(chords: lines[i].0, lyric: lines[i].1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .offset(y: offset)
            .frame(height: 250, alignment: .top)
            .clipped()
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                         .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            HStack {
                circle("chevron.left", 48)
                Spacer()
                circle("pause.fill", 56)
                Spacer()
                circle("chevron.right", 48)
            }
            .padding(.horizontal, 6)
        }
        .padding(.horizontal, 24)
        .onChange(of: active, initial: true) { _, on in
            guard on else { offset = 0; return }
            offset = 0
            withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) { offset = -270 }
        }
    }

    private func circle(_ icon: String, _ size: CGFloat) -> some View {
        Image(systemName: icon)
            .font(.system(size: 18, weight: .semibold))
            .frame(width: size, height: size)
            .glassEffect(in: .circle)
    }
}

/// Repertuarlarım ızgarası (uygulamadaki kartlar: ad + şarkı sayısı); yeni repertuar eklenir.
private struct RepertoireDemo: View {
    let active: Bool
    private let lists = [("Sahne · Cuma", 12), ("Kamp Ateşi", 8), ("Pratik", 5), ("Düğün Listesi", 21)]
    @State private var shown = 0

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
            ForEach(lists.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 2) {
                    Text(lists[i].0).font(.system(size: 16, weight: .bold)).lineLimit(2)
                    Text("\(lists[i].1) Şarkı").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .opacity(i < shown ? 1 : 0)
                .scaleEffect(i < shown ? 1 : 0.92)
            }
        }
        .padding(.horizontal, 24)
        .onChange(of: active, initial: true) { _, on in
            guard on else { shown = 0; return }
            for i in 0..<lists.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 + Double(i) * 0.3) {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { shown = i + 1 }
                }
            }
        }
    }
}

/// Yeni Şarkı formu (alanlar + akor metni) ve durum rozeti.
private struct AddSongDemo: View {
    let active: Bool
    @State private var st = 0
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 12) {
            field("Son Vapur")
            HStack(spacing: 12) {
                field("Kıyı")
                HStack {
                    Text("Am")
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .frame(width: 90, height: 48)
                .background(bg2, in: Capsule())
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Am          G\nSon vapur da çekti gitti\nF           E\nMartılar sustu, liman yalnız")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .lineSpacing(3)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(bg2, in: RoundedRectangle(cornerRadius: 16))
            HStack(spacing: 4) {
                Image(systemName: st == 0 ? "clock.fill" : "checkmark.seal.fill").font(.system(size: 10, weight: .bold))
                Text(st == 0 ? "Şarkınız onay bekliyor" : "Şarkınız yayında").font(.system(size: 10, weight: .bold))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background((st == 0 ? Color.orange : Color.green).opacity(0.15))
            .foregroundStyle(st == 0 ? Color.orange : Color.green)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentTransition(.opacity)
        }
        .font(.system(size: 16))
        .padding(.horizontal, 24)
        .onChange(of: active, initial: true) { _, on in
            timer?.invalidate()
            guard on else { st = 0; return }
            st = 0
            timer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: true) { _ in
                Task { @MainActor in withAnimation(.snappy) { st = (st + 1) % 2 } }
            }
        }
        .onDisappear { timer?.invalidate() }
    }

    private func field(_ text: String) -> some View {
        Text(text)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(bg2, in: Capsule())
    }
}

/// Şarkı sayfasının üst çubuğu (yer imi + paylaş ayrı daireler) ve paylaşılan adres; altında herkese açık profil satırı.
private struct ShareDemo: View {
    let active: Bool
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 22) {
            HStack(spacing: 8) {
                circle("chevron.left")
                Spacer()
                VStack(spacing: 1) {
                    Text("Sen Ağla").font(.system(size: 17, weight: .semibold))
                    Text("Sezen Aksu").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                circle("bookmark")
                circle("square.and.arrow.up")
                    .scaleEffect(pulse ? 1.12 : 1)
            }
            Text("gituar.com/akor/sezen-aksu/sen-agla/")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(Color.accentColor.opacity(0.1), in: Capsule())
                .opacity(pulse ? 1 : 0.35)

            HStack(spacing: 14) {
                Text("B")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 60, height: 60)
                    .background(Color.accentColor.opacity(0.15), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("@burak").font(.system(size: 18, weight: .bold))
                    Text("4 repertuar paylaşıyor").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .padding(.horizontal, 24)
        .onChange(of: active, initial: true) { _, on in
            guard on else { pulse = false; return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private func circle(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 17, weight: .semibold))
            .frame(width: 44, height: 44)
            .glassEffect(in: .circle)
    }
}

/// Ayarlardaki Çevrimdışı satırı ve indirme bildirimi (uygulamadakiyle aynı düzen).
private struct OfflineDemo: View {
    let active: Bool
    @State private var progress = 0.0
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Çevrimdışı").font(.system(size: 13)).foregroundStyle(.secondary).padding(.leading, 16)
                HStack {
                    Label("Tümünü İndir", systemImage: "icloud.and.arrow.down.fill")
                    Spacer()
                    Text("PRO")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.accentColor, in: Capsule())
                }
                .font(.system(size: 17))
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 10) {
                if progress < 1 {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Şarkılar indiriliyor").font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Text("%\(Int(progress * 100))").font(.system(size: 15, weight: .bold)).monospacedDigit()
                    }
                    ProgressView(value: progress).tint(.blue)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("İndirildi · şarkılar internetsiz de açılır")
                    }
                    .font(.system(size: 14, weight: .semibold))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(in: .rect(cornerRadius: 20))
        }
        .padding(.horizontal, 24)
        .onChange(of: active, initial: true) { _, on in
            timer?.invalidate()
            guard on else { progress = 0; return }
            progress = 0
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { t in
                Task { @MainActor in
                    if progress < 1 { progress = min(1, progress + 0.02) } else { t.invalidate() }
                }
            }
        }
        .onDisappear { timer?.invalidate() }
    }
}

#Preview {
    OnboardingView()
}
