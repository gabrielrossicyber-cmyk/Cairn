import SwiftUI

/// Écran affiché tant qu'aucun wiki n'est ouvert.
struct WelcomeView: View {
    @Environment(WikiStore.self) private var store

    var body: some View {
        VStack(spacing: 16) {
            Image("CairnMark")
                .resizable()
                .frame(width: 72, height: 72)
            Text("cairn")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            Text("Tes notes techniques, balisées pour retrouver ton chemin.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Un wiki = un dossier de pages Markdown. Tu peux en avoir plusieurs (brevet, projets, perso…).\nConseil : crée-les dans iCloud Drive pour les retrouver plus tard sur ton iPhone.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Créer un wiki…") { store.createWiki() }
                    .buttonStyle(.borderedProminent)
                Button("Ouvrir un wiki existant…") { store.chooseFolder() }
            }
            .controlSize(.large)
            if !store.wikis.isEmpty {
                Menu("Mes wikis") {
                    ForEach(store.wikis) { wiki in
                        Button(wiki.name) { store.openWiki(wiki.id) }
                    }
                }
                .fixedSize()
            }
        }
        .padding(40)
    }
}
