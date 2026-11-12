import Foundation

/// Variables, liens [[…]], favoris / récents et sommaire.
extension WikiStore {

    // MARK: Variables {{NOM}}

    /// Change la valeur d'une variable dans l'en-tête de la page (enregistré automatiquement).
    func setVariable(_ name: String, to value: String) {
        updateText(MarkdownPage.settingVariable(name, to: value, in: rawText))
    }

    // MARK: Liens [[…]]

    func rebuildPageLookup() {
        var lookup: [String: URL] = [:]
        for entry in searchIndex {
            for key in entry.keys where lookup[key] == nil {
                lookup[key] = entry.url
            }
        }
        pageLookup = lookup
        pageKeys = lookup.keys.sorted()
        let locked = Set(searchIndex.filter(\.isLocked).map { $0.url.standardizedFileURL.path })
        if locked != lockedPages { lockedPages = locked }
        rebuildTagIndex()
    }

    // MARK: Tags

    private func rebuildTagIndex() {
        var names: [String: String] = [:]
        var counts: [String: Int] = [:]
        for entry in searchIndex {
            for (tag, key) in zip(entry.tags, entry.tagKeys) {
                if names[key] == nil { names[key] = tag }
                counts[key, default: 0] += 1
            }
        }
        let tags = counts.map { TagInfo(key: $0.key, name: names[$0.key] ?? $0.key, count: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if tags != tagIndex { tagIndex = tags }
    }

    func tagName(_ key: String) -> String {
        tagIndex.first { $0.key == key }?.name ?? key
    }

    /// Ouvre la recherche filtrée sur ce tag (clic sur un tag dans une page ou la barre latérale).
    func openSearch(tag: String) {
        guard rootURL != nil else { return }
        searchTagFilter = SearchEngine.normalize(tag)
        isSearchPresented = true
    }

    /// Clic sur [[Nom]] : affiche la page dans le panneau de droite,
    /// ou la crée à côté de la page actuelle si elle n'existe pas.
    func openWikiLink(_ name: String) {
        let key = SearchEngine.normalize(name).trimmingCharacters(in: .whitespaces)
        if let url = pageLookup[key] {
            if url.standardizedFileURL.path == openURL?.standardizedFileURL.path { return }
            peekURL = url
            return
        }
        guard let folder = targetFolder(for: selectedNode) else { return }
        createPage(titled: name, in: folder, template: wikiSettings.defaultTemplate)
    }

    // MARK: Cases à cocher de l'aperçu

    /// Clic sur la n-ième case à cocher de l'aperçu : on coche / décoche dans le texte.
    func toggleTask(at index: Int) {
        let updated = MarkdownPage.togglingTask(at: index, in: rawText)
        if updated != rawText { updateText(updated) }
    }

    // MARK: Messages brefs

    func showToast(_ message: String) {
        toast = message
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            if self?.toast == message { self?.toast = nil }
        }
    }

    /// Pages proposées quand on tape « [[ » dans l'éditeur.
    var wikiLinkTargets: [WikiLinkTarget] {
        searchIndex.map { WikiLinkTarget(title: $0.title, path: $0.path) }
    }

    /// Pages qui contiennent un lien [[…]] vers cette page.
    func backlinks(for url: URL?) -> [SearchEntry] {
        guard let path = url?.standardizedFileURL.path,
              let entry = searchIndex.first(where: { $0.url.standardizedFileURL.path == path }) else { return [] }
        let keys = Set(entry.keys)
        return searchIndex
            .filter { $0.url.standardizedFileURL.path != path && !keys.isDisjoint(with: $0.links) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Informations pour l'aperçu : dossier de la page (images) et pages existantes (liens).
    var renderContext: RenderContext {
        RenderContext.current(base: openURL?.deletingLastPathComponent().path ?? "", pages: pageKeys)
    }

    // MARK: Favoris et récents

    private var pinnedDefaultsKey: String? {
        rootURL.map { "pinned:" + $0.standardizedFileURL.path }
    }

    func loadPinned() {
        guard let key = pinnedDefaultsKey,
              let stored = UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] else {
            favorites = []
            recents = []
            return
        }
        favorites = stored["favorites"] ?? []
        recents = stored["recents"] ?? []
    }

    private func savePinned() {
        guard let key = pinnedDefaultsKey else { return }
        UserDefaults.standard.set(["favorites": favorites, "recents": recents], forKey: key)
    }

    private func relativePath(_ url: URL) -> String? {
        guard let root = rootURL?.standardizedFileURL.path else { return nil }
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(root + "/") else { return nil }
        return String(path.dropFirst(root.count + 1))
    }

    private func absoluteURL(_ relative: String) -> URL? {
        rootURL?.appendingPathComponent(relative)
    }

    var favoriteNodes: [WikiNode] {
        favorites.compactMap { node(at: absoluteURL($0)) }
    }

    var recentNodes: [WikiNode] {
        Array(recents.compactMap { node(at: absoluteURL($0)) }.prefix(5))
    }

    func isFavorite(_ node: WikiNode) -> Bool {
        guard let relative = relativePath(node.url) else { return false }
        return favorites.contains(relative)
    }

    func toggleFavorite(_ node: WikiNode? = nil) {
        guard let node = node ?? selectedNode, let relative = relativePath(node.url) else { return }
        if let index = favorites.firstIndex(of: relative) {
            favorites.remove(at: index)
        } else {
            favorites.append(relative)
        }
        savePinned()
    }

    func clearRecents() {
        recents = []
        savePinned()
    }

    func recordRecent(_ url: URL) {
        guard let relative = relativePath(url) else { return }
        recents.removeAll { $0 == relative }
        recents.insert(relative, at: 0)
        if recents.count > 15 { recents.removeLast(recents.count - 15) }
        savePinned()
    }

    /// Après un renommage ou un déplacement : les favoris et récents suivent.
    func remapPinned(from old: URL, to new: URL) {
        guard let oldRelative = relativePath(old), let newRelative = relativePath(new) else { return }
        func remap(_ path: String) -> String {
            if path == oldRelative { return newRelative }
            if path.hasPrefix(oldRelative + "/") { return newRelative + path.dropFirst(oldRelative.count) }
            return path
        }
        favorites = favorites.map(remap)
        recents = recents.map(remap)
        savePinned()
    }

    /// Après une suppression : on retire l'élément (et son contenu) des favoris et récents.
    func removePinned(under url: URL) {
        guard let relative = relativePath(url) else { return }
        let keep: (String) -> Bool = { $0 != relative && !$0.hasPrefix(relative + "/") }
        favorites = favorites.filter(keep)
        recents = recents.filter(keep)
        savePinned()
    }

    // MARK: Sommaire

    func toggleOutline() {
        isOutlinePresented.toggle()
    }

    func scrollTo(_ heading: PageHeading) {
        tocRequest = TOCRequest(index: heading.index, title: heading.title, location: heading.location)
    }
}
