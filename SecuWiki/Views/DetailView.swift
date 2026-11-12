import SwiftUI

/// Partie droite : écran d'accueil, page sélectionnée ou message d'aide.
struct DetailView: View {
    @Environment(WikiStore.self) private var store

    var body: some View {
        if store.rootURL == nil {
            WelcomeView()
        } else if let node = store.selectedNode {
            if node.pageURL != nil {
                PageView(node: node, breadcrumb: store.breadcrumb(for: node))
            } else {
                ContentUnavailableView {
                    Label("Pas de page pour ce dossier", systemImage: "folder")
                } description: {
                    Text("Un dossier peut avoir sa propre page (fichier index.md), affichée quand tu cliques dessus.")
                } actions: {
                    Button("Créer la page du dossier") { store.createIndexPage(for: node) }
                }
            }
        } else {
            DashboardView()
        }
    }
}
