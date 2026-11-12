import Foundation

/// Un tag du wiki et le nombre de pages qui le portent.
struct TagInfo: Identifiable, Equatable, Hashable {
    /// Clé normalisée (sans accents, minuscules) : « ISO27001 » et « iso27001 » sont le même tag.
    let key: String
    /// Forme affichée (la première rencontrée).
    let name: String
    let count: Int

    var id: String { key }
}
