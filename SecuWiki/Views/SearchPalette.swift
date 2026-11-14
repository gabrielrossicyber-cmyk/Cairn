import SwiftUI
import AppKit

/// Palette de recherche (Cmd+K), façon Spotlight.
/// ↑↓ pour naviguer, Entrée pour ouvrir, Échap pour fermer.
/// Mode « Code » : cherche uniquement dans les blocs de code, avec un bouton Copier.
/// Filtres : dossier et tag (menus), ou « #tag » directement dans la recherche (« #iam kerberos »).
struct SearchPalette: View {
    @Environment(WikiStore.self) private var store
    @State private var query = ""
    @State private var codeOnly = false
    @State private var selected = 0
    @State private var isTagBrowserPresented = false
    @FocusState private var isFocused: Bool

    /// Mots à chercher et tags tapés (« #iam » -> filtre ; « #ia » marche aussi, par début de tag).
    private var parsedQuery: (text: String, tags: [String]) {
        var words: [String] = []
        var tags: [String] = []
        for token in query.split(separator: " ") {
            if token.hasPrefix("#"), token.count > 1 {
                tags.append(SearchEngine.normalize(String(token.dropFirst())))
            } else {
                words.append(String(token))
            }
        }
        return (words.joined(separator: " "), tags)
    }

    private var hasFilters: Bool {
        !store.searchFolderFilter.isEmpty || store.searchTagFilter != nil || !parsedQuery.tags.isEmpty
    }

    /// Pages dans le périmètre des filtres.
    private var scopedEntries: [SearchEntry] {
        var entries = store.entries(inFolder: store.searchFolderFilter)
        if let tag = store.searchTagFilter {
            entries = entries.filter { $0.tagKeys.contains(tag) }
        }
        for prefix in parsedQuery.tags {
            entries = entries.filter { entry in entry.tagKeys.contains { $0.hasPrefix(prefix) } }
        }
        return entries
    }

    private var results: [SearchResult] {
        SearchEngine.search(parsedQuery.text, in: scopedEntries, codeOnly: codeOnly, limit: hasFilters ? 200 : 50)
    }

    var body: some View {
        let results = self.results

        ZStack(alignment: .top) {
            // Clic en dehors : fermeture.
            Color.black.opacity(0.12)
                .ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                    TextField(codeOnly ? "Rechercher une commande…" : "Rechercher dans le wiki…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18))
                        .focused($isFocused)
                        .onSubmit { open(results) }
                        .onKeyPress(.downArrow) {
                            selected = min(selected + 1, max(self.results.count - 1, 0))
                            return .handled
                        }
                        .onKeyPress(.upArrow) {
                            selected = max(selected - 1, 0)
                            return .handled
                        }
                        .onKeyPress(.escape) {
                            close()
                            return .handled
                        }
                    Picker("", selection: $codeOnly) {
                        Text("Tout").tag(false)
                        Text("Code").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                .padding(14)

                filterBar
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)

                Divider()

                if results.isEmpty {
                    Text(emptyMessage)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(24)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                                    ResultRow(result: result, isSelected: index == selected)
                                        .id(index)
                                        .onTapGesture {
                                            selected = index
                                            open(results)
                                        }
                                }
                            }
                        }
                        .frame(maxHeight: 400)
                        .onChange(of: selected) { proxy.scrollTo(selected) }
                    }
                }

                Divider()
                Text("↑↓ naviguer · ↩ ouvrir · #tag filtrer · échap fermer · \(scopedEntries.count) / \(store.searchIndex.count) pages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }
            .frame(width: 660)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.1)))
            .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
            .padding(.top, 70)
        }
        .onAppear {
            DispatchQueue.main.async { isFocused = true }
        }
        .onChange(of: query) { selected = 0 }
        .onChange(of: codeOnly) { selected = 0 }
        .onChange(of: store.searchFolderFilter) { selected = 0 }
        .onChange(of: store.searchTagFilter) { selected = 0 }
        .onExitCommand { close() }
    }

    // MARK: Filtres

    private var filterBar: some View {
        HStack(spacing: 8) {
            Menu {
                Button("Tout le wiki") { store.searchFolderFilter = "" }
                Divider()
                ForEach(store.dashboardFolderOptions, id: \.self) { option in
                    Button(option.label) { store.searchFolderFilter = option.path }
                }
            } label: {
                Label(folderLabel, systemImage: "folder")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .foregroundStyle(store.searchFolderFilter.isEmpty ? Color.secondary : Color.accentColor)

            if !store.searchFolderFilter.isEmpty {
                clearButton { store.searchFolderFilter = "" }
            }

            Button {
                isTagBrowserPresented = true
            } label: {
                Label(store.searchTagFilter.map { "#" + store.tagName($0) } ?? "Tous les tags", systemImage: "number")
                    .lineLimit(1)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(store.searchTagFilter == nil ? Color.secondary : Color.cairnMoss)
            .disabled(store.tagIndex.isEmpty)
            .help(store.tagIndex.isEmpty ? "Aucun tag : ajoute « tags: iam, iso27001 » dans l'en-tête d'une page, ou #iam dans le texte." : "Filtrer par tag")
            .popover(isPresented: $isTagBrowserPresented, arrowEdge: .bottom) {
                TagBrowser { tag in
                    isTagBrowserPresented = false
                    store.searchTagFilter = tag.key
                }
            }

            if store.searchTagFilter != nil {
                clearButton { store.searchTagFilter = nil }
            }
            Spacer()
        }
        .font(.callout)
    }

    private var folderLabel: String {
        guard !store.searchFolderFilter.isEmpty else { return "Tout le wiki" }
        return store.searchFolderFilter.split(separator: "/").last.map(String.init).map(WikiScanner.displayName)
            ?? store.searchFolderFilter
    }

    private func clearButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.borderless)
        .help("Retirer ce filtre")
    }

    private var emptyMessage: String {
        if hasFilters && parsedQuery.text.isEmpty { return "Aucune page avec ces filtres." }
        if query.isEmpty { return codeOnly ? "Tape une commande : nmap, Get-WinEvent, iptables…" : "Aucune page pour l'instant." }
        return hasFilters ? "Aucun résultat pour « \(query) » avec ces filtres." : "Aucun résultat pour « \(query) »."
    }

    private func open(_ results: [SearchResult]) {
        guard results.indices.contains(selected) else { return }
        store.openPage(results[selected].entry.url)
        close()
    }

    private func close() {
        store.isSearchPresented = false
        store.searchTagFilter = nil // le filtre dossier, lui, reste (pratique pour réviser un module)
    }
}

/// Une ligne de résultat : titre, chemin, extrait.
private struct ResultRow: View {
    let result: SearchResult
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: result.snippetIsCode ? "terminal" : "doc.text")
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.entry.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(result.entry.path)
                        .lineLimit(1)
                    if !result.entry.tags.isEmpty {
                        Text(result.entry.tags.prefix(4).map { "#" + $0 }.joined(separator: " "))
                            .foregroundStyle(Color.cairnMoss)
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                if let snippet = result.snippet {
                    Text(snippet)
                        .font(result.snippetIsCode ? .system(size: 11, design: .monospaced) : .system(size: 12))
                        .foregroundStyle(Color.primary.opacity(0.75))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if result.snippetIsCode, let snippet = result.snippet {
                Button("Copier") {
                    SecretStore.copyResolving(snippet)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        .contentShape(Rectangle())
    }
}
