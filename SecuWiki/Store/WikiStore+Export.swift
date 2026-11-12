import AppKit
import UniformTypeIdentifiers

/// Recherche (Cmd+K) et export PDF / impression.
extension WikiStore {

    // MARK: Recherche

    func toggleSearch() {
        guard rootURL != nil else { return }
        isSearchPresented.toggle()
    }

    /// Sélectionne la page dont le fichier est `url` (page normale ou index.md d'un dossier).
    func openPage(_ url: URL) {
        let path = url.standardizedFileURL.path
        func find(_ list: [WikiNode]) -> WikiNode? {
            for node in list {
                if node.pageURL?.standardizedFileURL.path == path { return node }
                if let children = node.children, let found = find(children) { return found }
            }
            return nil
        }
        guard let node = find(nodes) else { return }
        selection = node.id
    }

    /// Met à jour l'index pour la page qu'on vient d'enregistrer (sans relire tout le wiki).
    func refreshSearchEntry(for url: URL, text: String) {
        guard let rootURL, let entry = SearchEngine.entry(for: url, root: rootURL, text: text) else { return }
        let path = url.standardizedFileURL.path
        if let index = searchIndex.firstIndex(where: { $0.url.standardizedFileURL.path == path }) {
            searchIndex[index] = entry
            rebuildPageLookup()
        }
    }

    // MARK: Export

    /// Titre de la page ouverte (en-tête YAML, sinon nom du fichier ou du dossier).
    var openPageTitle: String {
        guard let openURL else { return "Page" }
        if let title = MarkdownPage.parse(rawText).frontMatter["title"], !title.isEmpty { return title }
        if openURL.lastPathComponent.lowercased() == "index.md" {
            return WikiScanner.displayName(openURL.deletingLastPathComponent().lastPathComponent)
        }
        return WikiScanner.displayName(openURL.deletingPathExtension().lastPathComponent)
    }

    func exportPDF() {
        guard openURL != nil, loadError == nil, !isOpenPageLocked else { return }
        save()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = ((try? FileNaming.fileName(from: openPageTitle)) ?? "page") + ".pdf"
        panel.message = "Exporter « \(openPageTitle) » en PDF"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        runExport(.pdf(url)) {
            NSWorkspace.shared.open(url) // ouvre le PDF dans Aperçu
        }
    }

    func printPage() {
        guard openURL != nil, loadError == nil, !isOpenPageLocked else { return }
        save()
        runExport(.print, onSuccess: nil)
    }

    private func runExport(_ mode: PDFExporter.Mode, onSuccess: (() -> Void)?) {
        let page = MarkdownPage.parse(rawText)
        let markdown = MarkdownPage.substitute(page.body, variables: effectiveVariables(page))
        let exporter = PDFExporter()
        self.exporter = exporter // garde l'exporteur en vie pendant l'opération
        exporter.run(markdown: markdown, context: renderContext, mode: mode) { [weak self] error in
            if let error {
                self?.errorMessage = error
            } else {
                onSuccess?()
            }
            self?.exporter = nil
        }
    }
}
