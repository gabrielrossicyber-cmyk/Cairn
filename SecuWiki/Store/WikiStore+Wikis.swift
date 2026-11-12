import Foundation

/// Plusieurs wikis : création, ajout d'un dossier existant, retrait de la liste.
extension WikiStore {

    /// Ajoute un dossier à la liste des wikis (ou retrouve celui qui y est déjà). Retourne son identifiant.
    @discardableResult
    func addWiki(_ url: URL, name: String? = nil) -> UUID? {
        let path = url.standardizedFileURL.path
        if let existing = wikis.first(where: { $0.path == path }) { return existing.id }
        guard let reference = FolderAccess.reference(for: url, name: name ?? url.lastPathComponent) else {
            errorMessage = "Impossible d'enregistrer l'accès au dossier « \(url.lastPathComponent) »."
            return nil
        }
        wikis.append(reference)
        wikis.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        FolderAccess.saveList(wikis)
        return reference.id
    }

    /// Nouveau wiki : crée le dossier, ses réglages et une page d'accueil, puis l'ouvre.
    func createWiki() {
        guard let url = FolderAccess.pickNewWikiLocation() else { return }
        let fm = FileManager.default
        let name = url.lastPathComponent
        do {
            if !fm.fileExists(atPath: url.path) {
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
            }

            var settings = WikiSettings()
            settings.name = name
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(settings).write(to: url.appendingPathComponent(".secuwiki.json"), options: .atomic)

            let home = url.appendingPathComponent("00-Accueil.md")
            if !fm.fileExists(atPath: home.path) {
                let body = """
                Bienvenue dans le wiki **\(name)**.

                - Cmd+N : nouvelle page (avec choix du modèle)
                - Cmd+Maj+N : nouveau dossier
                - Cmd+K : rechercher dans le wiki
                - `/` dans l'éditeur : tableaux, commandes, schémas, modèles…
                """
                try PageTemplate.newPage(title: "Accueil", body: body).write(to: home, atomically: true, encoding: .utf8)
            }

            guard let id = addWiki(url, name: name) else { return }
            openWiki(id)
            showToast("Wiki « \(name) » créé")
        } catch {
            errorMessage = "Impossible de créer le wiki : \(error.localizedDescription)"
        }
    }

    /// Retire un wiki de la liste. Le dossier et ses pages ne sont PAS supprimés.
    func removeWiki(_ id: UUID) {
        guard let index = wikis.firstIndex(where: { $0.id == id }) else { return }
        let name = wikis[index].name
        let wasCurrent = id == currentWikiID
        wikis.remove(at: index)
        FolderAccess.saveList(wikis)

        if wasCurrent {
            if let next = wikis.first {
                openWiki(next.id)
            } else {
                closeWiki()
            }
        }
        showToast("« \(name) » retiré de la liste (le dossier n'est pas supprimé)")
    }

    /// Plus aucun wiki ouvert : retour à l'écran d'accueil.
    func closeWiki() {
        save()
        watcher = nil
        rootURL?.stopAccessingSecurityScopedResource()
        rootURL = nil
        currentWikiID = nil
        FolderAccess.currentID = nil
        selection = nil
        peekURL = nil
        closeFile()
        nodes = []
        searchIndex = []
        customTemplates = []
        wikiSettings = WikiSettings()
        loadPinned()
        rebuildPageLookup()
    }

    /// Garde le nom affiché dans le sélecteur de wikis à jour (Réglages > Général > Nom du wiki).
    func syncCurrentWikiName() {
        guard let id = currentWikiID, let index = wikis.firstIndex(where: { $0.id == id }) else { return }
        let name = wikiDisplayName
        guard wikis[index].name != name else { return }
        wikis[index].name = name
        FolderAccess.saveList(wikis)
    }
}
