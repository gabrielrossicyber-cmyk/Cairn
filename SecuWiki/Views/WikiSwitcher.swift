import SwiftUI

/// Sélecteur de wiki, en haut de la barre latérale : changer de wiki, en créer un, en ouvrir un.
struct WikiSwitcher: View {
    @Environment(WikiStore.self) private var store

    var body: some View {
        Menu {
            Section("Mes wikis") {
                ForEach(store.wikis) { wiki in
                    Button {
                        store.openWiki(wiki.id)
                    } label: {
                        if wiki.id == store.currentWikiID {
                            Label(wiki.name, systemImage: "checkmark")
                        } else {
                            Text(wiki.name)
                        }
                    }
                }
            }
            Divider()
            Button("Nouveau wiki…") { store.createWiki() }
            Button("Ouvrir un wiki existant…") { store.chooseFolder() }
            if !store.wikis.isEmpty {
                Divider()
                // N'importe quel wiki peut être retiré, même un dossier supprimé qu'on ne peut plus ouvrir.
                Menu("Retirer de la liste") {
                    ForEach(store.wikis) { wiki in
                        Button(wiki.name) { store.removeWiki(wiki.id) }
                    }
                    Divider()
                    Text("Le dossier et ses pages ne sont pas supprimés")
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "books.vertical.fill")
                    .foregroundStyle(Color.accentColor)
                Text(store.rootURL == nil ? "Aucun wiki" : store.wikiDisplayName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Changer de wiki, en créer un ou en ouvrir un")
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
