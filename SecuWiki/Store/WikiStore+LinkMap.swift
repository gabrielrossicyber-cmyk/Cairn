import Foundation

/// Carte des liens d'une page : qui la cite, ce qu'elle cite, et les pages qui partagent ses tags.
/// Volontairement locale (une page au centre, un seul niveau) : lisible, contrairement à un graphe global.
struct LinkMap {
    struct Target: Identifiable {
        /// Clé normalisée du lien [[…]].
        let id: String
        /// Texte du lien tel qu'écrit dans la page.
        let name: String
        /// Page existante, ou nil si le lien pointe vers une page à créer.
        let entry: SearchEntry?
    }

    struct TagGroup: Identifiable {
        let key: String
        let name: String
        let pages: [SearchEntry]
        let hiddenCount: Int
        var id: String { key }
    }

    let center: SearchEntry
    let incoming: [SearchEntry]
    let outgoing: [Target]
    let tagGroups: [TagGroup]

    var isEmpty: Bool { incoming.isEmpty && outgoing.isEmpty && tagGroups.isEmpty }
}

extension WikiStore {

    func toggleLinkMap() {
        guard openURL != nil else { return }
        save()
        isLinkMapPresented.toggle()
    }

    private static let rawLinkPattern = try! NSRegularExpression( // swiftlint:disable:this force_try
        pattern: "(!?)\\[\\[([^\\]|\\n]+)(?:\\|[^\\]\\n]+)?\\]\\]"
    )

    func linkMap(for url: URL) -> LinkMap? {
        let path = url.standardizedFileURL.path
        guard let center = searchIndex.first(where: { $0.url.standardizedFileURL.path == path }) else { return nil }
        let entriesByPath = Dictionary(searchIndex.map { ($0.url.standardizedFileURL.path, $0) }, uniquingKeysWith: { a, _ in a })

        let incoming = backlinks(for: url)

        // Liens sortants, dans l'ordre du texte. Les fichiers intégrés (![[doc.pdf]]) ne sont pas des pages.
        var outgoing: [LinkMap.Target] = []
        var seen = Set<String>()
        for line in center.lines {
            guard line.contains("[[") else { continue }
            let ns = line as NSString
            for match in Self.rawLinkPattern.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                guard ns.substring(with: match.range(at: 1)).isEmpty else { continue } // ![[…]] = fichier intégré
                let raw = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
                let key = SearchEngine.normalize(raw)
                guard !key.isEmpty, seen.insert(key).inserted else { continue }
                if let target = pageLookup[key] {
                    let targetPath = target.standardizedFileURL.path
                    guard targetPath != path, let entry = entriesByPath[targetPath] else { continue }
                    if outgoing.contains(where: { $0.entry?.url.standardizedFileURL.path == targetPath }) { continue }
                    outgoing.append(LinkMap.Target(id: key, name: raw, entry: entry))
                } else {
                    outgoing.append(LinkMap.Target(id: key, name: raw, entry: nil))
                }
            }
        }

        // Mêmes tags : les pages déjà reliées par un lien ne sont pas répétées.
        let linked = Set(incoming.map { $0.url.standardizedFileURL.path }
            + outgoing.compactMap { $0.entry?.url.standardizedFileURL.path } + [path])
        var groups: [LinkMap.TagGroup] = []
        for (name, key) in zip(center.tags, center.tagKeys).prefix(4) {
            let pages = searchIndex
                .filter { $0.tagKeys.contains(key) && !linked.contains($0.url.standardizedFileURL.path) }
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            if !pages.isEmpty {
                groups.append(LinkMap.TagGroup(key: key, name: name, pages: Array(pages.prefix(8)),
                                               hiddenCount: max(0, pages.count - 8)))
            }
        }

        return LinkMap(center: center, incoming: incoming, outgoing: outgoing, tagGroups: groups)
    }
}
