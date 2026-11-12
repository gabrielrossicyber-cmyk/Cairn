import SwiftUI

/// Affiche la page ouverte : fil d'Ariane, variables, puis lecture / édition, et les pages liées.
struct PageView: View {
    @Environment(WikiStore.self) private var store
    let node: WikiNode
    let breadcrumb: [String]
    private var prefs = PreviewPrefs()
    @AppStorage(Prefs.editorFontSize) private var editorFontSize = Prefs.Defaults.editorFontSize
    /// Défilement synchronisé éditeur -> aperçu (actif seulement en côte à côte).
    @State private var scrollSync = ScrollSync()

    init(node: WikiNode, breadcrumb: [String]) {
        self.node = node
        self.breadcrumb = breadcrumb
    }

    var body: some View {
        let page = MarkdownPage.parse(store.rawText)
        let _ = updateScrollSync(page)

        VStack(spacing: 0) {
            // En mode concentration : ni fil d'Ariane, ni barres annexes. Juste la page.
            if !store.isFocusMode {
                PageHeader(node: node, breadcrumb: breadcrumb)

                if store.loadError == nil && !store.isOpenPageLocked {
                    VariablesBar(page: page)
                }
            }

            if let loadError = store.loadError {
                ContentUnavailableView(
                    "Impossible de lire la page",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else if store.isOpenPageLocked {
                LockedPageView(title: breadcrumb.last ?? node.name)
            } else {
                if let peek = store.peekURL {
                    HSplitView {
                        content(page).frame(minWidth: 220, maxWidth: .infinity)
                        LinkedPagePanel(url: peek).frame(minWidth: 260, idealWidth: 380, maxWidth: .infinity)
                    }
                } else {
                    content(page)
                }
                if !store.isFocusMode { BacklinksBar() }
            }
        }
        // Fond « papier » uni : l'en-tête se fond dans la page, sans trait de séparation.
        .background(Color(nsColor: .textBackgroundColor))
        .navigationSubtitle(page.frontMatter["title"] ?? breadcrumb.last ?? "")
        .sheet(isPresented: Binding(get: { store.isSetPasswordPresented },
                                    set: { store.isSetPasswordPresented = $0 })) {
            SetPasswordSheet()
        }
    }

    @ViewBuilder
    private func content(_ page: MarkdownPage) -> some View {
        switch store.editorMode {
        case .preview:
            preview(page)
        case .edit:
            editor
        case .split:
            HSplitView {
                editor.frame(minWidth: 200, maxWidth: .infinity)
                preview(page).frame(minWidth: 200, maxWidth: .infinity)
            }
        }
    }

    private var editor: some View {
        MarkdownEditor(
            text: Binding(get: { store.rawText }, set: { store.updateText($0) }),
            documentID: store.openURL,
            pageProvider: { store.wikiLinkTargets },
            tocRequest: store.tocRequest,
            fontSize: editorFontSize,
            extraCommands: { store.customTemplates },
            scrollSync: scrollSync
        )
    }

    private func preview(_ page: MarkdownPage) -> some View {
        var context = prefs.context(base: store.openURL?.deletingLastPathComponent().path ?? "", pages: store.pageKeys)
        context.interactiveTasks = true
        return MarkdownWebView(
            markdown: MarkdownPage.substitute(page.body, variables: store.effectiveVariables(page)),
            pageID: store.openURL,
            context: context,
            tocRequest: store.tocRequest,
            onWikiLink: { store.openWikiLink($0) },
            onTag: { store.openSearch(tag: $0) },
            onToggleTask: { store.toggleTask(at: $0) },
            scrollSync: scrollSync
        )
    }

    /// Le défilement synchronisé ne sert qu'en mode côte à côte.
    private func updateScrollSync(_ page: MarkdownPage) {
        scrollSync.isEnabled = store.editorMode == .split
        scrollSync.headerLines = MarkdownPage.headerLineCount(store.rawText, body: page.body)
    }
}

/// Bandeau fin au-dessus de la page : chemin discret, état, favori (visible au survol).
private struct PageHeader: View {
    @Environment(WikiStore.self) private var store
    let node: WikiNode
    let breadcrumb: [String]
    @State private var isHovering = false
    @State private var confirmRemove = false

    var body: some View {
        let favorite = store.isFavorite(node)
        let tags = store.isOpenPageLocked ? [] : MarkdownPage.tags(in: store.rawText)
        HStack(spacing: 10) {
            Text(breadcrumb.joined(separator: "  /  "))
                .font(.caption)
                .foregroundStyle(.tertiary)
            // Tags de la page : un clic ouvre la recherche filtrée.
            ForEach(tags.prefix(6), id: \.self) { tag in
                Button("#" + tag) { store.openSearch(tag: tag) }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Color.cairnMoss)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.cairnMoss.opacity(0.12)))
                    .help("Pages avec #\(tag)")
            }
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
            SaveStatus()
            if store.openPageIsEncrypted && !store.isOpenPageLocked {
                // Page chiffrée, déverrouillée pour l'instant : un clic la referme.
                Menu {
                    Button("Verrouiller maintenant") { store.relockOpenPage() }
                    Button("Retirer le mot de passe…") { confirmRemove = true }
                } label: {
                    Image(systemName: "lock.open")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } primaryAction: {
                    store.relockOpenPage()
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Page chiffrée, déverrouillée. Clic : verrouiller (Cmd+L).")
            }
            Button { store.toggleLinkMap() } label: {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .opacity(isHovering ? 1 : 0)
            .help("Carte des liens de cette page (Cmd+Maj+M)")
            .disabled(store.isOpenPageLocked)
            Button { store.toggleFavorite(node) } label: {
                Image(systemName: favorite ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundStyle(favorite ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.borderless)
            .opacity(favorite || isHovering ? 1 : 0)
            .help(favorite ? "Retirer des favoris (Cmd+D)" : "Ajouter aux favoris (Cmd+D)")
        }
        .padding(.horizontal, 18)
        .frame(height: 30)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .confirmationDialog("Retirer le mot de passe ?", isPresented: $confirmRemove) {
            Button("Retirer le mot de passe", role: .destructive) { store.removeLock() }
        } message: {
            Text("La page sera de nouveau enregistrée en clair sur le disque.")
        }
    }
}

/// Indicateur d'enregistrement : rien quand c'est enregistré, un point pendant l'écriture.
private struct SaveStatus: View {
    @Environment(WikiStore.self) private var store

    var body: some View {
        Group {
            if let error = store.saveError {
                Label("Échec de l'enregistrement", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .help(error)
            } else if store.isDirty {
                // Un simple point discret : rien ne bouge quand tout est enregistré.
                Circle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 6, height: 6)
                    .help("Modifications en cours d'enregistrement")
            }
        }
        .font(.caption)
    }
}

/// Barre des variables : une case par {{NOM}} utilisé ou déclaré. Entrée pour valider.
/// Une variable globale (Réglages) apparaît en grisé tant que la page ne la redéfinit pas.
private struct VariablesBar: View {
    @Environment(WikiStore.self) private var store
    let page: MarkdownPage

    var body: some View {
        let declared = page.variables.map(\.name)
        let used = MarkdownPage.usedVariableNames(in: page.body).filter { !declared.contains($0) }
        let names = declared + used

        if !names.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    Label("Variables", systemImage: "curlybraces")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(names, id: \.self) { name in
                        VariableField(
                            name: name,
                            value: page.variables.first { $0.name == name }?.value ?? "",
                            placeholder: store.globalValue(of: name).map { "global : \($0)" } ?? "valeur"
                        )
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 5)
            }
        }
    }
}

private struct VariableField: View {
    @Environment(WikiStore.self) private var store
    let name: String
    let value: String
    let placeholder: String
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 5) {
            Text(name)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.teal)
            TextField("valeur", text: $text, prompt: Text(placeholder))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 150)
                .focused($isFocused)
                .onSubmit(commit)
        }
        .onAppear { text = value }
        .onChange(of: value) { if !isFocused { text = value } }
        .onChange(of: isFocused) { if !isFocused { commit() } }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed != value else { return }
        store.setVariable(name, to: trimmed)
    }
}

/// « Mentionnée dans » : les pages qui font un lien [[…]] vers cette page.
private struct BacklinksBar: View {
    @Environment(WikiStore.self) private var store

    var body: some View {
        let links = store.backlinks(for: store.openURL)
        if !links.isEmpty {
            VStack(spacing: 0) {
                Divider()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        Label("Mentionnée dans", systemImage: "arrow.uturn.backward")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(links) { entry in
                            Button(entry.title) { store.openPage(entry.url) }
                                .buttonStyle(.link)
                                .font(.caption)
                                .help(entry.path)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
            }
        }
    }
}
