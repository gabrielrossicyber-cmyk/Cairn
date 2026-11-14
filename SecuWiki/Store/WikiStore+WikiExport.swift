import AppKit

/// Avancement de l'export du wiki (affiché en bas de la fenêtre).
struct WikiExportProgress: Equatable {
    var done: Int
    var total: Int
    var current: String
}

/// Export du wiki entier : chaque page devient un PDF, rangé dans la même arborescence,
/// le tout compressé dans un .zip.
///
///   BF-CYBER-2026.zip
///   └── BF-CYBER-2026/
///       ├── 00-Accueil.pdf
///       └── 00_Modules/01_Fondamentaux/CAS_1-16.09.2026.pdf …
///
/// Les pages verrouillées ne sont jamais exportées (elles finiraient en clair dans le PDF).
/// Le dossier des modèles (_Modèles) est ignoré.
extension WikiStore {

    private struct ExportItem {
        let source: URL
        let relativePDF: String
        let title: String
    }

    func exportWikiAsZip() {
        guard let rootURL, wikiExport == nil else { return }
        save()
        let name = (try? FileNaming.fileName(from: wikiDisplayName)) ?? "Wiki"
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = name + ".zip"
        panel.message = "Exporter tout le wiki en PDF (une page = un PDF, mêmes dossiers)"
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        let items = exportItems(root: rootURL)
        guard !items.isEmpty else {
            errorMessage = "Ce wiki ne contient aucune page à exporter."
            return
        }
        Task { @MainActor in
            await runWikiExport(items, folderName: name, to: destination)
        }
    }

    func cancelWikiExport() {
        isWikiExportCancelled = true
    }

    // MARK: Étapes

    /// Toutes les pages, dans l'ordre de l'arborescence, avec leur chemin relatif (.md -> .pdf).
    private func exportItems(root: URL) -> [ExportItem] {
        let rootCount = root.standardizedFileURL.pathComponents.count
        var items: [ExportItem] = []
        func walk(_ list: [WikiNode]) {
            for node in list {
                if node.isFolder && SearchEngine.isTemplatesFolder(node.url.lastPathComponent) { continue }
                if let page = node.pageURL {
                    let parts = page.standardizedFileURL.pathComponents.dropFirst(rootCount)
                    let relative = (parts.joined(separator: "/") as NSString).deletingPathExtension + ".pdf"
                    items.append(ExportItem(source: page, relativePDF: relative, title: node.name))
                }
                if let children = node.children { walk(children) }
            }
        }
        walk(nodes)
        return items
    }

    @MainActor
    private func runWikiExport(_ items: [ExportItem], folderName: String, to destination: URL) async {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("Cairn-export-" + UUID().uuidString, isDirectory: true)
        let top = staging.appendingPathComponent(folderName, isDirectory: true)
        defer { try? fm.removeItem(at: staging) }

        isWikiExportCancelled = false
        wikiExport = WikiExportProgress(done: 0, total: items.count, current: "")
        var failures: [String] = []
        var lockedCount = 0

        for item in items {
            if isWikiExportCancelled { break }
            wikiExport?.current = item.title
            defer { wikiExport?.done += 1 }

            guard let text = try? String(contentsOf: item.source, encoding: .utf8) else {
                failures.append("• \(item.relativePDF) : lecture impossible")
                continue
            }
            if PageCrypto.isLocked(text) {
                lockedCount += 1
                continue
            }
            let page = MarkdownPage.parse(text)
            let markdown = MarkdownPage.substitute(page.body, variables: effectiveVariables(page))
            let target = top.appendingPathComponent(item.relativePDF)
            do {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            } catch {
                failures.append("• \(item.relativePDF) : \(error.localizedDescription)")
                continue
            }
            var context = RenderContext.current(base: item.source.deletingLastPathComponent().path, pages: pageKeys)
            context.secretNames = secretNames
            if let error = await renderPDF(markdown, context: context, to: target) {
                failures.append("• \(item.relativePDF) : \(error)")
            }
        }

        if isWikiExportCancelled {
            wikiExport = nil
            showToast("Export annulé")
            return
        }

        // Compression : macOS fournit le .zip d'un dossier via NSFileCoordinator (.forUploading),
        // sans outil externe et compatible avec le bac à sable de l'app.
        var zipError: Error?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: top, options: .forUploading, error: &coordinationError) { zipURL in
            do {
                if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
                try fm.copyItem(at: zipURL, to: destination)
            } catch {
                zipError = error
            }
        }
        wikiExport = nil

        if let error = zipError ?? coordinationError {
            errorMessage = "Impossible de créer le fichier .zip : \(error.localizedDescription)"
            return
        }
        let exported = items.count - failures.count - lockedCount
        showToast(exported == 1 ? "1 page exportée" : "\(exported) pages exportées")
        var notes: [String] = []
        if lockedCount > 0 {
            notes.append("\(lockedCount) page(s) verrouillée(s) non exportée(s) : elles seraient en clair dans le PDF.")
        }
        if !failures.isEmpty {
            notes.append("Pages en échec :\n" + failures.joined(separator: "\n"))
        }
        if !notes.isEmpty { errorMessage = notes.joined(separator: "\n\n") }
        NSWorkspace.shared.activateFileViewerSelecting([destination])
    }

    /// Une page -> un PDF (même rendu que l'export d'une page). Retourne un message d'erreur ou nil.
    @MainActor
    private func renderPDF(_ markdown: String, context: RenderContext, to url: URL) async -> String? {
        await withCheckedContinuation { continuation in
            let exporter = PDFExporter()
            self.exporter = exporter
            exporter.run(markdown: markdown, context: context, mode: .pdf(url)) { [weak self] error in
                self?.exporter = nil
                continuation.resume(returning: error)
            }
        }
    }
}
