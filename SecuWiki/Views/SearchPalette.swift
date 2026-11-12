import SwiftUI
import AppKit

/// Palette de recherche (Cmd+K), façon Spotlight.
/// ↑↓ pour naviguer, Entrée pour ouvrir, Échap pour fermer.
/// Mode « Code » : cherche uniquement dans les blocs de code, avec un bouton Copier.
struct SearchPalette: View {
    @Environment(WikiStore.self) private var store
    @State private var query = ""
    @State private var codeOnly = false
    @State private var selected = 0
    @FocusState private var isFocused: Bool

    private var results: [SearchResult] {
        SearchEngine.search(query, in: store.searchIndex, codeOnly: codeOnly)
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
                Text("↑↓ naviguer · ↩ ouvrir · échap fermer · \(store.searchIndex.count) pages indexées")
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
        .onExitCommand { close() }
    }

    private var emptyMessage: String {
        if query.isEmpty { return codeOnly ? "Tape une commande : nmap, Get-WinEvent, iptables…" : "Aucune page pour l'instant." }
        return "Aucun résultat pour « \(query) »."
    }

    private func open(_ results: [SearchResult]) {
        guard results.indices.contains(selected) else { return }
        store.openPage(results[selected].entry.url)
        close()
    }

    private func close() {
        store.isSearchPresented = false
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
                Text(result.entry.path)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(snippet, forType: .string)
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
