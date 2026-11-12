import SwiftUI

/// Fenêtre principale : arborescence à gauche, page à droite (style wiki Azure DevOps).
struct ContentView: View {
    @Environment(WikiStore.self) private var store
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    /// Écran de démarrage : durée minimale (animation) et sécurité si le chargement traîne (iCloud).
    @State private var splashMinimumElapsed = false
    @State private var splashGaveUp = false

    private var showsSplash: Bool {
        !splashGaveUp && (store.isLaunching || !splashMinimumElapsed)
    }

    var body: some View {
        @Bindable var store = store

        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 380)
        } detail: {
            DetailView()
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
        }
        // Sommaire : colonne à droite de toute la fenêtre (et non dans la zone centrale).
        .inspector(isPresented: $store.isOutlinePresented) {
            OutlinePanel()
        }
        .navigationTitle(store.wikiDisplayName)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Mode", selection: $store.editorMode) {
                    ForEach(EditorMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(store.openURL == nil || store.isOpenPageLocked)
                .help("Lecture (Cmd+1) · Édition (Cmd+2) · Côte à côte (Cmd+3)")
            }
            // Barre volontairement réduite : 3 boutons. Le reste vit dans « ⋯ » et dans les menus.
            ToolbarItemGroup(placement: .primaryAction) {
                Button { store.toggleSearch() } label: {
                    Label("Rechercher", systemImage: "magnifyingglass")
                }
                .help("Rechercher dans le wiki (Cmd+K)")
                .disabled(store.rootURL == nil)

                Menu {
                    Button("Nouvelle page…") { store.requestNewPage() }
                    Button("Nouveau dossier…") { store.requestNewFolder() }
                    Divider()
                    Button("Importer des documents…") { store.requestImport() }
                } label: {
                    Label("Ajouter", systemImage: "plus")
                }
                .menuIndicator(.hidden)
                .help("Nouvelle page (Cmd+N), dossier (Cmd+Maj+N) ou import (Cmd+Maj+I)")
                .disabled(store.rootURL == nil)

                Menu {
                    Button("Tableau de bord") { store.selection = nil }
                        .disabled(store.rootURL == nil)
                    Button(store.isOutlinePresented ? "Masquer le sommaire" : "Afficher le sommaire") {
                        store.toggleOutline()
                    }
                    Button(store.isFocusMode ? "Quitter le mode concentration" : "Mode concentration") {
                        store.isFocusMode.toggle()
                    }
                    .disabled(store.openURL == nil)
                    if store.openPageIsEncrypted {
                        Button("Verrouiller la page") { store.relockOpenPage() }
                            .disabled(store.isOpenPageLocked)
                    } else {
                        Button("Verrouiller avec un mot de passe…") { store.requestLockPage() }
                            .disabled(!store.canLockOpenPage)
                    }
                    Divider()
                    Button("Exporter en PDF…") { store.exportPDF() }
                        .disabled(store.openURL == nil || store.isOpenPageLocked)
                    Button("Imprimer…") { store.printPage() }
                        .disabled(store.openURL == nil || store.isOpenPageLocked)
                    Button("Exporter tout le wiki en PDF (.zip)…") { store.exportWikiAsZip() }
                        .disabled(store.rootURL == nil || store.wikiExport != nil)
                    Divider()
                    Button("Rafraîchir") { store.reload() }
                        .disabled(store.rootURL == nil)
                    Button("Nouveau wiki…") { store.createWiki() }
                    Button("Ouvrir un wiki existant…") { store.chooseFolder() }
                } label: {
                    Label("Plus", systemImage: "ellipsis.circle")
                }
                .menuIndicator(.hidden)
                .help("Tableau de bord, sommaire, concentration, export…")
            }
        }
        .onChange(of: store.selection) { store.openSelection() }
        // Mode concentration : masque l'arborescence, la retrouve en sortant.
        .onChange(of: store.isFocusMode) { _, focus in
            withAnimation(.easeInOut(duration: 0.2)) {
                columnVisibility = focus ? .detailOnly : .all
            }
        }
        .onChange(of: columnVisibility) { _, visibility in
            // Barre latérale rouverte à la main → on sort du mode concentration.
            if visibility != .detailOnly, store.isFocusMode { store.isFocusMode = false }
        }
        .onChange(of: store.openURL) { _, url in
            if url == nil { store.isFocusMode = false }
        }
        .overlay {
            if store.isSearchPresented { SearchPalette() }
        }
        // Message bref en bas de la fenêtre (« 3 liens mis à jour »…).
        .overlay(alignment: .bottom) {
            if let toast = store.toast {
                Text(toast)
                    .font(.callout)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color.black.opacity(0.8)))
                    .foregroundStyle(.white)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.toast)
        // Export du wiki entier : progression + annulation.
        .overlay(alignment: .bottom) {
            if let progress = store.wikiExport {
                WikiExportBanner(progress: progress)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.wikiExport == nil)
        // Écran de démarrage par-dessus tout, barre d'outils comprise.
        .overlay {
            if showsSplash {
                LaunchView(wikiName: store.wikis.first { $0.id == store.currentWikiID }?.name)
                    .transition(.opacity)
            }
        }
        .toolbar(showsSplash ? .hidden : .automatic, for: .windowToolbar)
        .animation(.easeOut(duration: 0.35), value: showsSplash)
        .task {
            try? await Task.sleep(for: .milliseconds(900))
            splashMinimumElapsed = true
            try? await Task.sleep(for: .seconds(8))
            splashGaveUp = true // le wiki continue de se charger, mais l'app reste utilisable
        }
        .modifier(WikiDialogs())
    }
}

/// Bandeau d'avancement de l'export du wiki.
private struct WikiExportBanner: View {
    @Environment(WikiStore.self) private var store
    let progress: WikiExportProgress

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Export du wiki en PDF… \(min(progress.done + 1, progress.total)) / \(progress.total)")
                    .font(.callout.weight(.medium))
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                    .frame(width: 260)
                Text(progress.current)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 260, alignment: .leading)
            }
            Button("Annuler") { store.cancelWikiExport() }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}

/// Fenêtres de saisie, de confirmation et d'erreur.
private struct WikiDialogs: ViewModifier {
    @Environment(WikiStore.self) private var store
    @State private var nameInput = ""

    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(get: { store.newPageRequest }, set: { store.newPageRequest = $0 })) { request in
                NewPageSheet(folder: request.folder)
                    .environment(store)
            }
            .alert(
                store.prompt?.title ?? "",
                isPresented: Binding(get: { store.prompt != nil }, set: { if !$0 { store.prompt = nil } }),
                presenting: store.prompt
            ) { prompt in
                TextField("Nom", text: $nameInput)
                Button("Annuler", role: .cancel) {}
                Button(prompt.confirmLabel) { store.perform(prompt, name: nameInput) }
            }
            .onChange(of: store.prompt?.id) { nameInput = store.prompt?.initialName ?? "" }
            .confirmationDialog(
                "Mettre « \(store.pendingDelete?.name ?? "") » à la corbeille ?",
                isPresented: Binding(get: { store.pendingDelete != nil }, set: { if !$0 { store.pendingDelete = nil } }),
                presenting: store.pendingDelete
            ) { node in
                Button("Mettre à la corbeille", role: .destructive) { store.delete(node) }
                Button("Annuler", role: .cancel) {}
            } message: { node in
                Text(node.isFolder
                     ? "Le dossier et tout son contenu iront à la corbeille."
                     : "Tu pourras la récupérer depuis la corbeille.")
            }
            .alert(
                "Opération impossible",
                isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
    }
}
