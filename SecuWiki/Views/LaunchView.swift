import SwiftUI

/// Écran de démarrage : le cairn se monte pierre par pierre pendant que le wiki se charge.
/// Il reste au minimum le temps de l'animation (≈ 0,9 s) puis disparaît en fondu dès que tout est prêt.
struct LaunchView: View {
    let wikiName: String?
    @State private var appeared = false

    /// Pierres du logo (même géométrie que Brand/cairn-mark.svg, cadre de 120 × 120).
    private struct Stone {
        let width: CGFloat
        let height: CGFloat
        let centerY: CGFloat
        let angle: Double
        let isTop: Bool
    }

    private let stones = [
        Stone(width: 84, height: 24, centerY: 92, angle: -2, isTop: false),
        Stone(width: 64, height: 21, centerY: 64.5, angle: 3, isTop: false),
        Stone(width: 44, height: 19, centerY: 40.5, angle: -4, isTop: true),
    ]

    private static let ink = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.90, green: 0.89, blue: 0.85, alpha: 1)
            : NSColor(red: 0.11, green: 0.17, blue: 0.18, alpha: 1)
    })
    private static let moss = Color(red: 0.24, green: 0.56, blue: 0.49)

    var body: some View {
        VStack(spacing: 18) {
            ZStack(alignment: .top) {
                ForEach(Array(stones.enumerated()), id: \.offset) { index, stone in
                    Capsule()
                        .fill(stone.isTop ? Self.moss : Self.ink)
                        .frame(width: stone.width, height: stone.height)
                        .rotationEffect(.degrees(stone.angle))
                        .position(x: 60, y: stone.centerY)
                        .offset(y: appeared ? 0 : -36)
                        .opacity(appeared ? 1 : 0)
                        .animation(.spring(response: 0.42, dampingFraction: 0.68).delay(0.12 * Double(index)), value: appeared)
                }
            }
            .frame(width: 120, height: 120)

            Text("cairn")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(Self.ink)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.4), value: appeared)

            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(wikiName.map { "Chargement de « \($0) »…" } ?? "Chargement…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.4).delay(0.55), value: appeared)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { appeared = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Chargement de Cairn")
    }
}
