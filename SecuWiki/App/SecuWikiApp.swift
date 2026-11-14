import SwiftUI

/// Point d'entrée de l'application.
@main
struct SecuWikiApp: App {
    /// L'état global du wiki (dossier racine, arborescence, page ouverte).
    @State private var store = WikiStore()
    @AppStorage(Prefs.appearance) private var appearance = Prefs.Defaults.appearance
    @AppStorage(Prefs.quickCaptureEnabled) private var quickCaptureEnabled = Prefs.Defaults.quickCaptureEnabled
    /// Raccourcis clavier (Réglages › Raccourcis) : les menus se mettent à jour dès qu'ils changent.
    @AppStorage(Prefs.shortcuts) private var shortcutsJSON = ""

    private func key(_ action: ShortcutAction) -> KeyboardShortcut? {
        ShortcutSettings.load(from: shortcutsJSON).shortcut(for: action)
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(store)
                .frame(minWidth: store.requiredMinWidth, minHeight: 550)
                .onAppear {
                    Prefs.applyAppearance(appearance)
                    QuickCaptureController.shared.configure(store: store)
                }
                .onChange(of: appearance) { _, value in Prefs.applyAppearance(value) }
                .onChange(of: quickCaptureEnabled) { QuickCaptureController.shared.updateHotKey() }
                .onChange(of: shortcutsJSON) { QuickCaptureController.shared.updateHotKey() }
        }
        // La fenêtre ne peut pas être plus petite que son contenu (plus de débordement).
        .windowResizability(.contentMinSize)

        .commands {
            // Menu Fichier
            CommandGroup(replacing: .newItem) {
                Button("Nouvelle page…") { store.requestNewPage() }
                    .keyboardShortcut(key(.newPage))
                    .disabled(store.rootURL == nil)
                Button("Nouveau dossier…") { store.requestNewFolder() }
                    .keyboardShortcut(key(.newFolder))
                    .disabled(store.rootURL == nil)
                Button("Importer des documents…") { store.requestImport() }
                    .keyboardShortcut(key(.importDocuments))
                    .disabled(store.rootURL == nil)
                Divider()
                Button("Nouveau wiki…") { store.createWiki() }
                    .keyboardShortcut(key(.newWiki))
                Button("Ouvrir un wiki existant…") { store.chooseFolder() }
                    .keyboardShortcut(key(.openWiki))
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
                    .keyboardShortcut(key(.save))
                    .disabled(store.openURL == nil)
            }
            CommandGroup(replacing: .printItem) {
                Button("Exporter en PDF…") { store.exportPDF() }
                    .keyboardShortcut(key(.exportPDF))
                    .disabled(store.openURL == nil)
                Button("Imprimer…") { store.printPage() }
                    .keyboardShortcut(key(.printPage))
                    .disabled(store.openURL == nil)
                Divider()
                Button("Exporter tout le wiki en PDF (.zip)…") { store.exportWikiAsZip() }
                    .keyboardShortcut(key(.exportWiki))
                    .disabled(store.rootURL == nil || store.wikiExport != nil)
            }
            // Menu Format (agit sur l'éditeur actif)
            CommandMenu("Format") {
                Button("Gras") { MarkdownTextView.perform(#selector(MarkdownTextView.markdownBold(_:))) }
                    .keyboardShortcut(key(.bold))
                Button("Italique") { MarkdownTextView.perform(#selector(MarkdownTextView.markdownItalic(_:))) }
                    .keyboardShortcut(key(.italic))
                Button("Code") { MarkdownTextView.perform(#selector(MarkdownTextView.markdownInlineCode(_:))) }
                    .keyboardShortcut(key(.inlineCode))
                Divider()
                Button("Insérer un tableau") { MarkdownTextView.perform(#selector(MarkdownTextView.markdownInsertTable(_:))) }
                    .keyboardShortcut(key(.insertTable))
                Button("Insérer une commande bash") { MarkdownTextView.perform(#selector(MarkdownTextView.markdownInsertCode(_:))) }
                    .keyboardShortcut(key(.insertCode))
                Divider()
                Text("Astuce : tape / dans l'éditeur pour toutes les commandes")
            }
            // Menu Page
            CommandMenu("Page") {
                Button("Rechercher dans le wiki…") { store.toggleSearch() }
                    .keyboardShortcut(key(.search))
                    .disabled(store.rootURL == nil)
                Button("Tableau de bord") { store.selection = nil }
                    .keyboardShortcut(key(.dashboard))
                    .disabled(store.rootURL == nil)
                Button("Mode examen…") { store.startExam() }
                    .keyboardShortcut(key(.exam))
                    .disabled(store.rootURL == nil)
                Button(store.isLinkMapPresented ? "Revenir à la page" : "Carte des liens") { store.toggleLinkMap() }
                    .keyboardShortcut(key(.linkMap))
                    .disabled(store.openURL == nil || store.isOpenPageLocked)
                Divider()
                ForEach(EditorMode.allCases) { mode in
                    Button(mode.label) { store.editorMode = mode }
                        .keyboardShortcut(key(mode.shortcutAction))
                }
                Divider()
                Button("Sommaire") { store.toggleOutline() }
                    .keyboardShortcut(key(.outline))
                Button(store.isFocusMode ? "Quitter le mode concentration" : "Mode concentration") {
                    store.isFocusMode.toggle()
                }
                .keyboardShortcut(key(.focusMode))
                .disabled(store.openURL == nil)
                Button("Ajouter / retirer des favoris") { store.toggleFavorite() }
                    .keyboardShortcut(key(.favorite))
                    .disabled(store.selectedNode == nil)
                Divider()
                if store.openPageIsEncrypted {
                    Button("Verrouiller maintenant") { store.relockOpenPage() }
                        .keyboardShortcut(key(.lock))
                        .disabled(store.isOpenPageLocked)
                    Button("Retirer le mot de passe") { store.removeLock() }
                        .disabled(store.isOpenPageLocked)
                } else {
                    Button("Verrouiller avec un mot de passe…") { store.requestLockPage() }
                        .keyboardShortcut(key(.lock))
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
                    .keyboardShortcut(key(.reload))
                    .disabled(store.rootURL == nil)
            }

            // Menu Aide : la page guide du wiki (recréée si elle a été supprimée).
            CommandGroup(replacing: .help) {
                Button("Guide de Cairn") { store.openGuide() }
                    .disabled(store.rootURL == nil)
            }
        }

        // Fenêtre Réglages (menu SecuWiki > Réglages…, Cmd+,)
        // Icône dans la barre des menus : capture rapide (⌃⌥N), même fenêtre fermée.
        MenuBarExtra("Cairn", systemImage: "square.and.pencil", isInserted: $quickCaptureEnabled) {
            MenuBarContent()
        }

        Settings {
            SettingsView()
                .environment(store)
        }
    }
}
