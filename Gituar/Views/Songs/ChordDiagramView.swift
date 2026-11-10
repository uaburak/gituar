import SwiftUI

/// Akor diyagramı (web'deki chord-svg.ts ile aynı çizim): 6 tel, 5 perde, açık/çalınmayan tel işaretleri, barre.
struct ChordDiagramView: View {
    let shape: ChordShapes.Shape

    var body: some View {
        Canvas { ctx, size in
            let played = shape.frets.filter { $0 > 0 }
            let minFret = played.min() ?? 1
            let maxFret = played.max() ?? 1
            let start = maxFret <= 5 ? 1 : minFret
            // Web'deki 100 × 120 çizimin ölçeklenmiş hâli
            let k = min(size.width / 100, size.height / 120)
            let left = 14 * k, top = 22 * k, sx = 14.4 * k, sy = 18 * k
            func x(_ s: Int) -> CGFloat { left + CGFloat(s) * sx }
            func y(_ f: Int) -> CGFloat { top + (CGFloat(f - start) + 0.5) * sy }
            let ink = GraphicsContext.Shading.color(.primary)
            let dot = GraphicsContext.Shading.color(.blue)

            if start == 1 {
                ctx.fill(Path(CGRect(x: x(0), y: top - 3 * k, width: x(5) - x(0), height: 3 * k)), with: ink)
            } else {
                ctx.draw(Text("\(start)").font(.system(size: 11 * k, weight: .medium)).foregroundColor(.secondary),
                         at: CGPoint(x: left - 7 * k, y: y(start)), anchor: .trailing)
            }
            var grid = Path()
            for i in 0..<6 {
                grid.move(to: CGPoint(x: x(0), y: top + CGFloat(i) * sy)); grid.addLine(to: CGPoint(x: x(5), y: top + CGFloat(i) * sy))
                grid.move(to: CGPoint(x: x(i), y: top)); grid.addLine(to: CGPoint(x: x(i), y: top + 5 * sy))
            }
            ctx.stroke(grid, with: .color(.secondary.opacity(0.6)), lineWidth: max(1, 0.8 * k))

            let barre = (shape.barre ?? 0) >= start ? shape.barre : nil
            let barreStrings = barre.map { b in shape.frets.indices.filter { shape.frets[$0] == b } } ?? []
            if let barre, barreStrings.count > 1, let a = barreStrings.first, let b = barreStrings.last {
                let r = CGRect(x: x(a) - 5 * k, y: y(barre) - 5 * k, width: x(b) - x(a) + 10 * k, height: 10 * k)
                ctx.fill(Path(roundedRect: r, cornerRadius: 5 * k), with: dot)
            }
            for (s, f) in shape.frets.enumerated() {
                if f == -1 {
                    ctx.draw(Text("×").font(.system(size: 12 * k)).foregroundColor(.secondary), at: CGPoint(x: x(s), y: top - 10 * k))
                } else if f == 0 {
                    let r = 3.2 * k
                    ctx.stroke(Path(ellipseIn: CGRect(x: x(s) - r, y: top - 10 * k - r, width: 2 * r, height: 2 * r)), with: ink, lineWidth: max(1, 1.1 * k))
                } else if !(barre == f && barreStrings.count > 1) {
                    let r = 5 * k
                    ctx.fill(Path(ellipseIn: CGRect(x: x(s) - r, y: y(f) - r, width: 2 * r, height: 2 * r)), with: dot)
                }
            }
        }
        .aspectRatio(100 / 120, contentMode: .fit)
        .accessibilityLabel("Akor diyagramı")
    }
}

/// Kâğıttaki akora dokununca açılan kart: diyagram, tutuş adı, tekrar çal ve diğer tutuş.
struct ChordPopupCard: View {
    let chord: String
    let capo: Int
    let onClose: () -> Void
    @State private var index = 0

    private var shapes: [ChordShapes.Shape] { ChordShapes.shapes(for: chord) }

    var body: some View {
        let list = shapes
        HStack(spacing: 16) {
            if list.isEmpty {
                Text("Bu akorun tutuşu yok")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(width: 96, height: 116)
            } else {
                ChordDiagramView(shape: list[index % list.count])
                    .frame(width: 96, height: 116)
                    .contentShape(Rectangle())
                    .onTapGesture { play(list[index % list.count]) }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(chord)
                    .font(.system(size: 22, weight: .bold))
                if !list.isEmpty {
                    Text(list[index % list.count].name)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if capo > 0 {
                        Text("Kapo \(capo). perdede")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 8) {
                        Button {
                            play(list[index % list.count])
                        } label: {
                            Label("Çal", systemImage: "speaker.wave.2.fill")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        if list.count > 1 {
                            Button {
                                index = (index + 1) % list.count
                                play(list[index])
                            } label: {
                                Text("Diğer tutuş")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 30, height: 30)
            }
            .accessibilityLabel("Kapat")
            .padding(8)
        }
        .glassEffect(in: .rect(cornerRadius: 24))
        .onChange(of: chord) { _, _ in index = 0 }
    }

    private func play(_ shape: ChordShapes.Shape) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        ChordPlayer.shared.play(frets: shape.frets, capo: capo)
    }
}
