import Foundation

/// Page « Guide Cairn » : toutes les fonctions de l'app, avec des exemples vivants.
///
/// - Créée à la racine de chaque nouveau wiki.
/// - Menu Aide › Guide de Cairn : l'ouvre, ou la recrée si elle a été supprimée
///   (utile aussi pour les wikis créés avant cette fonction).
/// - Son texte est le fichier `Guide/Guide-Cairn.md` de l'app : pour le mettre à jour, modifier ce fichier.
extension WikiStore {
    static let guideFileName = "Guide-Cairn.md"

    /// Contenu complet de la page (en-tête avec un tag et une variable d'exemple + texte du guide).
    static func guidePageContent() -> String {
        var header = PageTemplate.header(title: "Guide Cairn")
        let closing = "---\n\n"
        if header.hasSuffix(closing) {
            header = String(header.dropLast(closing.count))
                + "tags: guide\nvars:\n  IP_CIBLE: 10.10.10.10\n" + closing
        }
        let bundled = Bundle.main.url(forResource: "Guide-Cairn", withExtension: "md")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        let body = bundled ?? "# Guide Cairn\n\nTape `/` dans l'éditeur pour voir toutes les commandes, et Cmd+K pour chercher.\n"
        return header + body
    }

    /// Écrit le guide à la racine du wiki s'il n'y est pas déjà. Retourne son adresse.
    @discardableResult
    static func writeGuide(in root: URL) throws -> URL {
        let url = root.appendingPathComponent(guideFileName)
        if !FileManager.default.fileExists(atPath: url.path) {
            try guidePageContent().write(to: url, atomically: true, encoding: .utf8)
            OrderFile.append(WikiNode.orderKey(for: url, isFolder: false), in: root)
        }
        return url
    }

    /// Menu Aide › Guide de Cairn.
    func openGuide() {
        guard let rootURL else { return }
        let existed = FileManager.default.fileExists(atPath: rootURL.appendingPathComponent(Self.guideFileName).path)
        do {
            let url = try Self.writeGuide(in: rootURL)
            if !existed {
                reload()
                showToast("Guide ajouté à la racine du wiki")
            }
            openPage(url)
        } catch {
            errorMessage = "Impossible de créer le guide : \(error.localizedDescription)"
        }
    }
}
