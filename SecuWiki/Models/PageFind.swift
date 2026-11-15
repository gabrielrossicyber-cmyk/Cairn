import Foundation

/// Demande envoyée à l'aperçu : chercher un texte dans la page, passer au résultat suivant, tout effacer.
struct FindRequest: Equatable {
    enum Kind: Equatable {
        case search, next, previous, clear
    }

    let id = UUID()
    var kind: Kind
    var query = ""
    /// Ligne du corps de la page où se placer d'abord (résultat choisi dans Cmd+K). nil : à partir de l'écran.
    var line: Int?
    /// Lancée en ouvrant un résultat de Cmd+K : si le texte n'est pas dans la page, la barre ne s'affiche pas.
    var isAutomatic = false
}

/// Demande envoyée à l'éditeur : sélectionner un passage et le faire défiler à l'écran.
struct EditorJump: Equatable {
    let id = UUID()
    let range: NSRange
    /// Donner le curseur à l'éditeur (mode Édition). En côte à côte, la barre de recherche garde le clavier.
    let takesFocus: Bool
}

/// Résultat de Cmd+K à ouvrir « au bon endroit » dès que sa page est chargée.
struct PendingJump {
    let path: String
    let query: String
    let line: Int?
}
