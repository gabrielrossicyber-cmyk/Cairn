import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Import de documents : chaque document devient une page du wiki.
///
/// | Format                         | Résultat                                                        |
/// |--------------------------------|-----------------------------------------------------------------|
/// | Markdown, texte                | page (l'en-tête d'un .md existant est conservé)                 |
/// | Word, RTF, HTML, OpenDocument  | page convertie en Markdown (titres, listes, gras, liens)        |
/// | PDF                            | PDF rangé dans assets/, affiché dans la page + texte extrait    |
/// | Image                          | image rangée dans assets/ + page qui l'affiche                  |
extension WikiStore {

    static let importableTypes: [UTType] = [.pdf, .plainText, .rtf, .rtfd, .html, .image] + [
        UTType(filenameExtension: "md"),
        UTType(filenameExtension: "markdown"),
        UTType("org.openxmlformats.wordprocessingml.document"),
        UTType("com.microsoft.word.doc"),
        UTType("org.oasis-open.opendocument.text"),
    ].compactMap { $0 }

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "svg", "bmp"]

    /// Fenêtre de sélection des documents à importer (dans le dossier sélectionné).
    func requestImport(near node: WikiNode? = nil) {
        guard let folder = targetFolder(for: node ?? selectedNode) else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = Self.importableTypes
        panel.prompt = "Importer"
        panel.message = "PDF, Word, RTF, HTML, Markdown, texte ou images : chaque document devient une page."
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        importDocuments(panel.urls, into: folder)
    }

    func importDocuments(_ urls: [URL], into folder: URL) {
        save()
        var created: [URL] = []
        var failures: [String] = []
        let rootPath = rootURL?.standardizedFileURL.path ?? ""

        for url in urls {
            // Fichier déjà dans le wiki (glissé depuis le Finder) : simple déplacement.
            if !rootPath.isEmpty, url.standardizedFileURL.path.hasPrefix(rootPath + "/") {
                if let existing = self.node(at: url) { move(existing, to: folder) }
                continue
            }
            do {
                created.append(try importDocument(url, into: folder))
            } catch {
                failures.append("• \(url.lastPathComponent) : \(error.localizedDescription)")
            }
        }

        guard !created.isEmpty || !failures.isEmpty else { return }
        reload()
        if let last = created.last { openPage(last) }
        if !created.isEmpty {
            showToast(created.count == 1 ? "1 document importé" : "\(created.count) documents importés")
        }
        if !failures.isEmpty {
            errorMessage = "Certains documents n'ont pas pu être importés :\n" + failures.joined(separator: "\n")
        }
    }

    /// Importe un document et retourne la page créée.
    private func importDocument(_ url: URL, into folder: URL) throws -> URL {
        let ext = url.pathExtension.lowercased()
        let title = url.deletingPathExtension().lastPathComponent
        let page = uniquePageURL(for: title, in: folder)
        let content: String

        switch ext {
        case "md", "markdown", "txt", "text":
            let text = try readText(url)
            if ext != "txt" && text.hasPrefix("---\n") {
                content = text // page Markdown complète : on la garde telle quelle
            } else {
                content = PageTemplate.header(title: title) + text
            }

        case "pdf":
            let asset = try copyAsset(url, into: folder)
            var body = "![[assets/\(asset.lastPathComponent)]]\n"
            let extracted = (PDFDocument(url: url)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !extracted.isEmpty {
                // Texte du PDF dans un encadré repliable : lisible au besoin et trouvable avec Cmd+K.
                let limited = extracted.count > 150_000 ? String(extracted.prefix(150_000)) + "\n… (texte tronqué)" : extracted
                let quoted = limited.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .map { $0.isEmpty ? ">" : "> " + $0 }
                    .joined(separator: "\n")
                body += "\n> [!EXTRAIT]\n" + quoted + "\n"
            }
            content = PageTemplate.newPage(title: title, body: body)

        case _ where Self.imageExtensions.contains(ext):
            let asset = try copyAsset(url, into: folder)
            let encoded = asset.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? asset.lastPathComponent
            content = PageTemplate.newPage(title: title, body: "![\(title)](assets/\(encoded))\n")

        default:
            // Word, RTF, HTML, OpenDocument : lus par macOS puis convertis en Markdown.
            let document: NSAttributedString
            if ["html", "htm", "xhtml"].contains(ext) {
                // HTML : rien ne doit partir sur le réseau pendant l'import (images pisteuses, scripts…).
                let html = Self.neutralizedHTML(try readText(url))
                document = try NSAttributedString(
                    data: Data(html.utf8),
                    options: [.documentType: NSAttributedString.DocumentType.html,
                              .characterEncoding: String.Encoding.utf8.rawValue],
                    documentAttributes: nil
                )
            } else {
                document = try NSAttributedString(url: url, options: [:], documentAttributes: nil)
            }
            content = PageTemplate.newPage(title: title, body: MarkdownConverter.markdown(from: document))
        }

        try content.write(to: page, atomically: true, encoding: .utf8)
        OrderFile.append(WikiNode.orderKey(for: page, isFolder: false), in: folder)
        return page
    }

    // MARK: Outils

    /// Retire du HTML tout ce qui pourrait être chargé ou exécuté : scripts, cadres, objets,
    /// feuilles de style externes, et attributs qui déclenchent un téléchargement (src, srcset…).
    static func neutralizedHTML(_ html: String) -> String {
        var result = html
        let patterns = [
            "(?is)<script\\b.*?</script\\s*>",
            "(?is)<(iframe|object|embed|frame|frameset|applet|audio|video)\\b.*?(</\\1\\s*>|/>|>)",
            "(?is)<link\\b[^>]*>",
            "(?is)<meta\\b[^>]*http-equiv[^>]*>",
            "(?is)<base\\b[^>]*>",
        ]
        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        // src="…" -> data-blocked-src="…" : l'image n'est pas téléchargée.
        result = result.replacingOccurrences(
            of: "(?i)\\b(src|srcset|background|poster|lowsrc|dynsrc)\\s*=",
            with: "data-blocked-$1=",
            options: .regularExpression
        )
        // url(...) dans les styles en ligne
        result = result.replacingOccurrences(of: "(?i)url\\s*\\(", with: "blocked(", options: .regularExpression)
        return result
    }

    private func readText(_ url: URL) throws -> String {
        if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        var encoding = String.Encoding.utf8
        return try String(contentsOf: url, usedEncoding: &encoding)
    }

    /// Nom de page libre : « Titre.md », sinon « Titre-2.md »…
    private func uniquePageURL(for title: String, in folder: URL) -> URL {
        let base = (try? FileNaming.fileName(from: title)) ?? "Document"
        var candidate = folder.appendingPathComponent(base).appendingPathExtension("md")
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base)-\(number)").appendingPathExtension("md")
            number += 1
        }
        return candidate
    }

    /// Copie un fichier dans le dossier assets/ (à côté des pages) sous un nom libre.
    private func copyAsset(_ url: URL, into folder: URL) throws -> URL {
        let fm = FileManager.default
        let assets = folder.appendingPathComponent("assets", isDirectory: true)
        try fm.createDirectory(at: assets, withIntermediateDirectories: true)
        let ext = url.pathExtension.lowercased()
        let base = (try? FileNaming.fileName(from: url.deletingPathExtension().lastPathComponent)) ?? "fichier"
        var candidate = assets.appendingPathComponent(base).appendingPathExtension(ext)
        var number = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = assets.appendingPathComponent("\(base)-\(number)").appendingPathExtension(ext)
            number += 1
        }
        try fm.copyItem(at: url, to: candidate)
        return candidate
    }
}
