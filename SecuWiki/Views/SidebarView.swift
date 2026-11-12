import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Barre latérale : sélecteur de wiki, favoris, pages récentes, puis l'arborescence.
/// Clic droit = menu d'actions ; glisser une page sur un dossier = déplacer ;
/// glisser un document depuis le Finder = l'importer dans ce dossier.
struct SidebarView: View {
    @Environment(WikiStore.self) private var store
    @AppStorage("sidebar.showFavorites") private var showFavorites = true
    @AppStorage("sidebar.showRecents") private var showRecents = true
    @AppStorage("sidebar.showTags") private var showTags = false

    var body: some View {
        // @Bindable permet de créer un binding ($store.selection) vers un objet @Observable.
        @Bindable var store = store
        let favorites = store.favoriteNodes
        let recents = store.recentNodes

        List(selection: $store.selection) {
            // Favoris et récents : identifiants propres à chaque section (« fav: », « rec: »),
            // sinon la liste confond ces lignes avec celles de l'arborescence.
            if !favorites.isEmpty {
                Section("Favoris", isExpanded: $showFavorites) {
                    ForEach(favorites.map { PinnedItem(prefix: "fav", node: $0) }) { item in
                        PinnedRow(node: item.node, icon: "star")
                    }
                }
            }
            if !recents.isEmpty {
                Section("Récents", isExpanded: $showRecents) {
                    ForEach(recents.map { PinnedItem(prefix: "rec", node: $0) }) { item in
                        PinnedRow(node: item.node, icon: "clock")
                    }
                }
            }
            Section("Pages") {
                OutlineGroup(store.nodes, children: \.children) { node in
                    NodeRow(node: node)
                }
            }
            // Tags : un clic ouvre la recherche filtrée (lignes sans tag : pas de sélection).
            if !store.tagIndex.isEmpty {
                Section("Tags", isExpanded: $showTags) {
                    ForEach(store.tagIndex) { tag in
                        Button { store.openSearch(tag: tag.key) } label: {
                            HStack {
                                Label("#" + tag.name, systemImage: "number")
                                    .labelStyle(.titleOnly)
                                Spacer()
                                Text("\(tag.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        // Liste neuve à chaque changement de wiki (évite les restes d'affichage).
        .id(store.currentWikiID)
        // Sélecteur de wiki en haut de la barre latérale.
        .safeAreaInset(edge: .top, spacing: 0) {
            WikiSwitcher()
        }
        // Document déposé dans le vide de la barre latérale : importé à la racine.
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let root = store.rootURL else { return false }
            return SidebarDrop.handle(providers, into: root, store: store)
        }
        .overlay {
            if store.rootURL != nil && store.nodes.isEmpty {
                ContentUnavailableView {
                    Label("Wiki vide", systemImage: "tray")
                } description: {
                    Text("Crée ta première page, ou glisse ici des documents à importer.")
                } actions: {
                    Button("Nouvelle page…") { store.requestNewPage() }
                    Button("Importer des documents…") { store.requestImport() }
                }
            }
        }
    }
}

/// Élément des sections Favoris / Récents, avec un identifiant unique par section.
private struct PinnedItem: Identifiable {
    let id: String
    let node: WikiNode

    init(prefix: String, node: WikiNode) {
        self.id = prefix + ":" + node.url.path
        self.node = node
    }
}

/// Ligne Favoris / Récents : un clic ouvre la page (la sélection reste dans l'arborescence).
private struct PinnedRow: View {
    @Environment(WikiStore.self) private var store
    let node: WikiNode
    let icon: String

    var body: some View {
        let isCurrent = store.selection?.standardizedFileURL.path == node.url.standardizedFileURL.path
        Label {
            Text(node.name)
                .fontWeight(isCurrent ? .semibold : .regular)
                .lineLimit(1)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { store.selection = node.id }
        .contextMenu { NodeContextMenu(node: node) }
    }
}

/// Une ligne de l'arborescence.
private struct NodeRow: View {
    @Environment(WikiStore.self) private var store
    let node: WikiNode

    var body: some View {
        Label {
            Text(node.name)
                .lineLimit(1)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
        }
        .tag(node.id)
        // API glisser-déposer « classique » : plus stable que .draggable dans une liste
        // hiérarchique (l'autre laissait des restes d'affichage : texte dédoublé).
        .onDrag { NSItemProvider(object: node.url.path as NSString) }
        .onDrop(of: [.fileURL, .plainText], isTargeted: nil) { providers in
            // Déposé sur un dossier : dedans. Déposé sur une page : à côté d'elle.
            let folder = node.isFolder ? node.url : node.url.deletingLastPathComponent()
            return SidebarDrop.handle(providers, into: folder, store: store)
        }
        .contextMenu { NodeContextMenu(node: node) }
    }

    private var icon: String {
        if node.isFolder { return node.pageURL != nil ? "folder.fill" : "folder" }
        return store.isLockedPage(node.pageURL ?? node.url) ? "lock.doc" : "doc.text"
    }
}

/// Dépôt dans la barre latérale : page du wiki (déplacement) ou document du Finder (import).
private enum SidebarDrop {
    static func handle(_ providers: [NSItemProvider], into folder: URL, store: WikiStore) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { store.importDocuments([url], into: folder) }
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                handled = true
                _ = provider.loadObject(ofClass: NSString.self) { item, _ in
                    guard let path = item as? String else { return }
                    DispatchQueue.main.async {
                        if let source = store.node(at: URL(fileURLWithPath: path)) {
                            store.move(source, to: folder)
                        }
                    }
                }
            }
        }
        return handled
    }
}

/// Menu du clic droit sur un élément.
private struct NodeContextMenu: View {
    @Environment(WikiStore.self) private var store
    let node: WikiNode

    var body: some View {
        Button("Nouvelle page ici…") { store.requestNewPage(near: node) }
        Button("Nouveau dossier ici…") { store.requestNewFolder(near: node) }
        Button("Importer des documents ici…") { store.requestImport(near: node) }
        if node.isFolder && node.pageURL == nil {
            Button("Créer la page du dossier") { store.createIndexPage(for: node) }
        }
        Divider()
        Button(store.isFavorite(node) ? "Retirer des favoris" : "Ajouter aux favoris") {
            store.toggleFavorite(node)
        }
        Button("Renommer…") { store.requestRename(node) }
        Button("Dupliquer") { store.duplicate(node) }
        Menu("Déplacer vers") {
            ForEach(store.folderOptions(excluding: node)) { option in
                Button(option.label) { store.move(node, to: option.url) }
            }
        }
        Button("Monter") { store.reorder(node, by: -1) }
        Button("Descendre") { store.reorder(node, by: 1) }
        Divider()
        Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
        Divider()
        Button("Mettre à la corbeille…", role: .destructive) { store.requestDelete(node) }
    }
}
