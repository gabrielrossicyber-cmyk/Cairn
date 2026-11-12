import Foundation
import SwiftUI

/// Un tag du wiki et le nombre de pages qui le portent.
struct TagInfo: Identifiable, Equatable, Hashable {
    /// Clé normalisée (sans accents, minuscules) : « ISO27001 » et « iso27001 » sont le même tag.
    let key: String
    /// Forme affichée (la première rencontrée).
    let name: String
    let count: Int

    var id: String { key }
}

extension Color {
    /// Vert mousse de Cairn (tags) : fixe, ne dépend pas de la couleur d'accent choisie dans macOS.
    static let cairnMoss = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.37, green: 0.70, blue: 0.62, alpha: 1)
            : NSColor(calibratedRed: 0.24, green: 0.56, blue: 0.49, alpha: 1)
    })
}
