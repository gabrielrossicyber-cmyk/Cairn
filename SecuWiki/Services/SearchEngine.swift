import Foundation

/// Une page dans l'index de recherche (construit en mémoire, aucune base de données).
struct SearchEntry: Identifiable {
    let url: URL
    let title: String
    /// Fil d'Ariane : "Réseau › Nmap".
    let path: String
    /// Lignes non vides du corps de la page.
    let lines: [String]
    /// Pour chaque ligne : est-elle dans un bloc de code ?
    let isCode: [Bool]
    /// Noms sous lesquels on peut lier cette page avec [[…]] (titre et nom de fichier, normalisés).
    let keys: [String]
    /// Pages vers lesquelles cette page fait un lien [[…]] (noms normalisés).
    let links: [String]
    /// Date de dernière modification (tableau de bord).
    var modified: Date?
    /// Page chiffrée : seul son titre est indexé.
    var isLocked = false
    /// Tags de la page (tels qu'écrits) et leurs clés normalisées (sans accents, minuscules).
    let tags: [String]
    let tagKeys: [String]

    fileprivate let normalizedTitle: String
    fileprivate let normalizedPath: String
    fileprivate let normalizedLines: [String]
    fileprivate let normalizedAll: String

    var id: URL { url }

    private static let linkPattern = try! NSRegularExpression( // swiftlint:disable:this force_try
        pattern: "\\[\\[([^\\]|\\n]+)(?:\\|[^\\]\\n]+)?\\]\\]"
    )

    init(url: URL, title: String, fileName: String, path: String, body: String, tags: [String] = []) {
        var lines: [String] = []
        var isCode: [Bool] = []
        var links: [String] = []
        var inFence = false
        for raw in body.components(separatedBy: "\n") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inFence.toggle()
                continue
            }
            guard !trimmed.isEmpty else { continue }
            lines.append(trimmed)
            isCode.append(inFence)
            if !inFence, trimmed.contains("[[") {
                let ns = trimmed as NSString
                for match in Self.linkPattern.matches(in: trimmed, range: NSRange(location: 0, length: ns.length)) {
                    let target = SearchEngine.normalize(ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces))
                    if !links.contains(target) { links.append(target) }
                }
            }
        }

        self.url = url
        self.title = title
        self.path = path
        self.lines = lines
        self.isCode = isCode
        self.links = links
        let titleKey = SearchEngine.normalize(title).trimmingCharacters(in: .whitespaces)
        let fileKey = SearchEngine.normalize(fileName).trimmingCharacters(in: .whitespaces)
        self.keys = titleKey == fileKey ? [titleKey] : [titleKey, fileKey]
        self.normalizedTitle = SearchEngine.normalize(title)
        self.normalizedPath = SearchEngine.normalize(path)
        self.normalizedLines = lines.map(SearchEngine.normalize)
        self.tags = tags
        self.tagKeys = tags.map(SearchEngine.normalize)
        // Les tags de l'en-tête sont aussi trouvables par la recherche texte.
        self.normalizedAll = ([normalizedTitle, normalizedPath] + normalizedLines + tagKeys).joined(separator: "\n")
    }
}

/// Un résultat affiché dans la palette Cmd+K.
struct SearchResult: Identifiable {
    let entry: SearchEntry
    /// Ligne de la page qui correspond le mieux à la recherche.
    let snippet: String?
    let snippetIsCode: Bool
    let score: Int
    var id: URL { entry.url }
}

/// Recherche plein texte : tous les mots tapés doivent être présents (sans tenir compte
/// des accents ni des majuscules). Le titre compte plus que le chemin, qui compte plus que le texte.
enum SearchEngine {

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    }

    // MARK: Index

    /// Dossier des modèles personnels (exclu de la recherche et des liens).
    static func isTemplatesFolder(_ name: String) -> Bool {
        ["_modeles", "_templates"].contains(normalize(name))
    }

    /// Index de toutes les pages. `previous` (index précédent, par chemin) évite de relire
    /// les fichiers inchangés : seule la date de modification est consultée (très rapide).
    /// Sans ce cache, chaque enregistrement automatique relisait toutes les pages du wiki.
    static func buildIndex(nodes: [WikiNode], root: URL, previous: [String: SearchEntry] = [:]) -> [SearchEntry] {
        var entries: [SearchEntry] = []
        func walk(_ list: [WikiNode]) {
            for node in list {
                if node.isFolder && isTemplatesFolder(node.url.lastPathComponent) { continue }
                if let page = node.pageURL {
                    let path = page.standardizedFileURL.path
                    let modified = (try? page.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    if let cached = previous[path], modified != nil, cached.modified == modified {
                        entries.append(cached)
                    } else if let entry = entry(for: page, root: root) {
                        entries.append(entry)
                    }
                }
                if let children = node.children { walk(children) }
            }
        }
        walk(nodes)
        return entries
    }

    /// Construit l'entrée d'une page. `text` évite de relire le fichier quand on l'a déjà.
    static func entry(for url: URL, root: URL, text: String? = nil) -> SearchEntry? {
        guard let content = text ?? (try? String(contentsOf: url, encoding: .utf8)) else { return nil }
        let page = MarkdownPage.parse(content)

        let rootCount = root.standardizedFileURL.pathComponents.count
        var parts = Array(url.standardizedFileURL.pathComponents.dropFirst(rootCount))
        if parts.count > 1, parts.last?.lowercased() == "index.md" {
            parts.removeLast() // index.md = la page du dossier
        } else if let last = parts.last {
            parts[parts.count - 1] = (last as NSString).deletingPathExtension
        }
        let names = parts.map(WikiScanner.displayName)
        let title = page.frontMatter["title"].flatMap { $0.isEmpty ? nil : $0 } ?? names.last ?? url.lastPathComponent

        // Page verrouillée : le contenu chiffré n'est pas indexé (il ne serait que du base64).
        let locked = PageCrypto.isLocked(content)
        var entry = SearchEntry(url: url, title: title, fileName: names.last ?? title,
                                path: names.joined(separator: " › "), body: locked ? "" : page.body,
                                tags: locked ? [] : MarkdownPage.tags(in: content))
        entry.isLocked = locked
        // Date réelle du fichier (sert aussi de clé du cache de l'index) ; « maintenant » s'il vient d'être écrit.
        var fileURL = url
        fileURL.removeAllCachedResourceValues()
        entry.modified = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            ?? (text != nil ? Date.now : nil)
        return entry
    }

    // MARK: Recherche

    static func search(_ query: String, in entries: [SearchEntry], codeOnly: Bool, limit: Int = 50) -> [SearchResult] {
        let terms = normalize(query).split(separator: " ").map(String.init)

        guard !terms.isEmpty else {
            // Rien de tapé : toutes les pages par ordre alphabétique.
            if codeOnly { return [] }
            return entries
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                .prefix(limit)
                .map { SearchResult(entry: $0, snippet: nil, snippetIsCode: false, score: 0) }
        }

        var results: [SearchResult] = []
        for entry in entries {
            if codeOnly {
                // Seulement les lignes de code qui contiennent tous les mots.
                let matching = entry.normalizedLines.indices.filter { index in
                    entry.isCode[index] && terms.allSatisfy { entry.normalizedLines[index].contains($0) }
                }
                guard let first = matching.first else { continue }
                let titleBonus = terms.contains { entry.normalizedTitle.contains($0) } ? 5 : 0
                results.append(SearchResult(entry: entry, snippet: entry.lines[first], snippetIsCode: true,
                                            score: matching.count + titleBonus))
            } else {
                guard terms.allSatisfy({ entry.normalizedAll.contains($0) }) else { continue }

                var score = 0
                for term in terms {
                    if entry.normalizedTitle.contains(term) { score += 10 }
                    else if entry.normalizedPath.contains(term) { score += 4 }
                    else { score += 1 }
                }
                if entry.normalizedTitle.hasPrefix(terms[0]) { score += 5 }

                // Extrait : la ligne qui contient le plus de mots recherchés.
                var best: Int?
                var bestCount = 0
                for (index, line) in entry.normalizedLines.enumerated() {
                    let count = terms.filter { line.contains($0) }.count
                    if count > bestCount {
                        bestCount = count
                        best = index
                        if count == terms.count { break }
                    }
                }
                results.append(SearchResult(
                    entry: entry,
                    snippet: best.map { entry.lines[$0] },
                    snippetIsCode: best.map { entry.isCode[$0] } ?? false,
                    score: score
                ))
            }
        }

        let sorted = results.sorted {
            $0.score != $1.score
                ? $0.score > $1.score
                : $0.entry.title.localizedStandardCompare($1.entry.title) == .orderedAscending
        }
        return Array(sorted.prefix(limit))
    }
}
