import SwiftUI

/// Point d'entrée de l'application.
@main
struct SecuWikiApp: App {
    /// L'état global du wiki (dossier racine, arborescence, page ouverte).
    @State private var store = WikiStore()
    @AppStorage(Prefs.appearance) private var appearance = Prefs.Defaults.appearance

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .frame(minWidth: store.requiredMinWidth, minHeight: 550)
                .onAppear { Prefs.applyAppearance(appearance) }
                .onChange(of: appearance) { _, value in Prefs.applyAppearance(value) }
        }
        // La fenêtre ne peut pas être plus petite que son contenu (plus de débordement).
        .windowResizability(.contentMinSize)

        .commands {
            // Menu Fichier
            CommandGroup(replacing: .newItem) {
                Button("Nouvelle page…") { store.requestNewPage() }
                    .keyboardShortcut("n")
                    .disabled(store.rootURL == nil)
                Button("Nouveau dossier…") { store.requestNewFolder() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .disabled(store.rootURL == nil)
                Button("Importer des documents…") { store.requestImport() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                    .disabled(store.rootURL == nil)
                Divider()
                Button("Nouveau wiki…") { store.createWiki() }
                    .keyboardShortcut("n", modifiers: [.command, .option])
                Button("Ouvrir un wiki existant…") { store.chooseFolder() }
                    .keyboardShortcut("o")
                Menu("Changer de wiki") {
                    ForEach(store.wikis) { wiki in
                        Button(wiki.name) { store.openWiki(wiki.id) }
                            .disabled(wiki.id == store.currentWikiID)
                    }
                }
                .disabled(store.wikis.count < 2)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Enregistrer") { store.save() }
                    .keyboardShortcut("s")
                    .disabled(store.openURL == nil)
            }
            CommandGroup(replacing: .printItem) {
                Button("Exporter en PDF…") { store.exportPDF() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(store.openURL == nil)
                Button("Imprimer…") { store.printPage() }
                    .keyboardShortcut("p")
                    .disabled(store.openURL == nil)
                Divider()
                Button("Exporter tout le wiki en PDF (.zip)…") { store.exportWikiAsZip() }
                    .keyboardShortcut("e", modifiers: [.command, .option])
                    .disabled(store.rootURL == nil || store.wikiExport != nil)
            }
            // Menu Format (agit sur l'éditeur actif)
            CommandMenu("Format") {
                Button("Gras") { MarkdownTextView.perform(#selector(MarkdownTextView.markdownBold(_:))) }
                    .keyboardShortcut("b")
                Button("Italique") { MarkdownTextView.perform(#selector(MarkdownTextView.markdownItalic(_:))) }
                    .keyboardShortcut("i")
                Button("Code") { MarkdownTextView.perform(#selector(MarkdownTextView.markdownInlineCode(_:))) }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Divider()
                Button("Insérer un tableau") { MarkdownTextView.perform(#selector(MarkdownTextView.markdownInsertTable(_:))) }
                    .keyboardShortcut("t", modifiers: [.command, .option])
                Button("Insérer une commande bash") { MarkdownTextView.perform(#selector(MarkdownTextView.markdownInsertCode(_:))) }
                    .keyboardShortcut("c", modifiers: [.command, .option])
                Divider()
                Text("Astuce : tape / dans l'éditeur pour toutes les commandes")
            }
            // Menu Page
            CommandMenu("Page") {
                Button("Rechercher dans le wiki…") { store.toggleSearch() }
                    .keyboardShortcut("k")
                    .disabled(store.rootURL == nil)
                Button("Tableau de bord") { store.selection = nil }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                    .disabled(store.rootURL == nil)
                Button("Mode examen…") { store.startExam() }
                    .keyboardShortcut("x", modifiers: [.command, .shift])
                    .disabled(store.rootURL == nil)
                Button(store.isLinkMapPresented ? "Revenir à la page" : "Carte des liens") { store.toggleLinkMap() }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                    .disabled(store.openURL == nil || store.isOpenPageLocked)
                Divider()
                ForEach(EditorMode.allCases) { mode in
                    Button(mode.label) { store.editorMode = mode }
                        .keyboardShortcut(mode.shortcut)
                }
                Divider()
                Button("Sommaire") { store.toggleOutline() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button(store.isFocusMode ? "Quitter le mode concentration" : "Mode concentration") {
                    store.isFocusMode.toggle()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(store.openURL == nil)
                Button("Ajouter / retirer des favoris") { store.toggleFavorite() }
                    .keyboardShortcut("d")
                    .disabled(store.selectedNode == nil)
                Divider()
                if store.openPageIsEncrypted {
                    Button("Verrouiller maintenant") { store.relockOpenPage() }
                        .keyboardShortcut("l")
                        .disabled(store.isOpenPageLocked)
                    Button("Retirer le mot de passe") { store.removeLock() }
                        .disabled(store.isOpenPageLocked)
                } else {
                    Button("Verrouiller avec un mot de passe…") { store.requestLockPage() }
                        .keyboardShortcut("l")
                        .disabled(!store.canLockOpenPage)
                }
                Button("Verrouiller toutes les pages") { store.lockAllPages() }
                    .disabled(store.lockSessions.isEmpty)
                Divider()
                Button("Renommer…") { store.requestRename() }
                    .disabled(store.selectedNode == nil)
                Button("Dupliquer") { if let node = store.selectedNode { store.duplicate(node) } }
                    .disabled(store.selectedNode == nil)
                Button("Mettre à la corbeille…") { store.requestDelete() }
                    .disabled(store.selectedNode == nil)
                Divider()
                Button("Rafraîchir") { store.reload() }
                    .keyboardShortcut("r")
                    .disabled(store.rootURL == nil)
            }
        }

        // Fenêtre Réglages (menu SecuWiki > Réglages…, Cmd+,)
        Settings {
            SettingsView()
                .environment(store)
        }
    }
}
