import Foundation

/// Fenêtre de saisie d'un nom (nouvelle page, nouveau dossier, renommage).
struct NamePrompt: Identifiable {
    enum Action {
        case newPage(in: URL)
        case newFolder(in: URL)
        case rename(WikiNode)
    }

    let id = UUID()
    let action: Action

    var title: String {
        switch action {
        case .newPage: return "Nouvelle page"
        case .newFolder: return "Nouveau dossier"
        case .rename(let node): return "Renommer « \(node.name) »"
        }
    }

    var confirmLabel: String {
        if case .rename = action { return "Renommer" }
        return "Créer"
    }

    var initialName: String {
        if case .rename(let node) = action { return node.name }
        return ""
    }
}

/// Fenêtre « Nouvelle page » (titre + choix du modèle).
struct NewPageRequest: Identifiable {
    let id = UUID()
    let folder: URL
}

/// Destination proposée dans le menu « Déplacer vers ».
struct FolderOption: Identifiable {
    let url: URL
    let label: String
    var id: String { url.path }
}

/// Erreur affichée à l'utilisateur.
struct WikiError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
