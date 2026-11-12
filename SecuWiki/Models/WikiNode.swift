import Foundation

/// Un élément de l'arborescence : un dossier (section) ou une page Markdown.
struct WikiNode: Identifiable, Hashable {
    /// L'URL du fichier ou du dossier sert d'identifiant unique.
    let id: URL
    /// Nom affiché dans la barre latérale.
    let name: String
    let isFolder: Bool
    /// Sous-éléments. `nil` = pas de flèche de dépliage (exigé par List/OutlineGroup).
    var children: [WikiNode]?
    /// Fichier Markdown à afficher quand on sélectionne ce nœud
    /// (la page elle-même, ou index.md pour un dossier).
    var pageURL: URL?

    var url: URL { id }
}

extension WikiNode {
    /// Nom utilisé dans le fichier `.order` : nom du dossier, ou nom du fichier sans `.md`.
    var orderKey: String { Self.orderKey(for: url, isFolder: isFolder) }

    static func orderKey(for url: URL, isFolder: Bool) -> String {
        let raw = isFolder ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        // Normalisation Unicode : « é » peut être stocké de deux façons sur le disque.
        return raw.precomposedStringWithCanonicalMapping
    }
}
