import SwiftUI
import Observation
import AppKit

/// L'état central de l'app. Les vues le lisent via `@Environment(WikiStore.self)`
/// et se redessinent automatiquement quand une propriété change (@Observable).
///
/// Les opérations sur les fichiers (créer, renommer, déplacer…) sont dans WikiStore+Files.swift.
@Observable
final class WikiStore {
    // MARK: Wiki

    /// Dossier racine du wiki ouvert.
    var rootURL: URL?
    /// Tous les wikis connus (sélecteur en haut de la barre latérale).
    var wikis: [WikiReference] = []
    var currentWikiID: UUID?
    /// Arborescence affichée à gauche.
    var nodes: [WikiNode] = []
    /// Identifiant (URL) du nœud sélectionné.
    var selection: URL?

    // MARK: Page ouverte

    /// Fichier actuellement ouvert.
    var openURL: URL?
    /// Contenu complet du fichier (en-tête YAML compris), tel qu'il est dans l'éditeur.
    var rawText = ""
    /// Contenu tel qu'il est sur le disque, pour savoir s'il reste des modifications à enregistrer.
    var savedText = ""
    var loadError: String?
    var saveError: String?
    var editorMode: EditorMode = .preview
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    var isDirty: Bool { rawText != savedText }

    // MARK: Recherche et export

    /// Palette Cmd+K affichée.
    var isSearchPresented = false
    /// Index de recherche en mémoire (reconstruit à chaque Cmd+R, mis à jour à chaque enregistrement).
    var searchIndex: [SearchEntry] = []
    @ObservationIgnored var exporter: PDFExporter?
    /// Export du wiki entier en cours (barre de progression), nil sinon.
    var wikiExport: WikiExportProgress?
    @ObservationIgnored var isWikiExportCancelled = false

    // MARK: Favoris, récents, liens [[…]], sommaire

    /// Chemins relatifs à la racine.
    var favorites: [String] = []
    var recents: [String] = []
    /// Nom de page normalisé -> fichier (pour résoudre les liens [[…]]).
    var pageLookup: [String: URL] = [:]
    /// Mêmes noms, triés (envoyés à l'aperçu pour colorer les liens cassés).
    var pageKeys: [String] = []
    var isOutlinePresented = false
    /// La page ouverte est chiffrée sur le disque (voir WikiStore+Lock.swift).
    var openPageIsEncrypted = false
    /// Clés des pages déverrouillées, en mémoire uniquement (clé = chemin du fichier).
    var lockSessions: [String: LockSession] = [:]
    /// Chemins des pages verrouillées (icône cadenas dans l'arborescence).
    var lockedPages: Set<String> = []
    /// Fenêtre « Verrouiller avec un mot de passe » affichée.
    var isSetPasswordPresented = false
    @ObservationIgnored var lockObservers: [NSObjectProtocol] = []
    /// Mode concentration : seule la page reste à l'écran.
    var isFocusMode = false
    var tocRequest: TOCRequest?
    /// Page affichée dans le panneau de droite après un clic sur [[…]].
    var peekURL: URL?
    /// Réglages du wiki (fichier .secuwiki.json à la racine).
    var wikiSettings = WikiSettings()
    /// Modèles personnels (fichiers .md du dossier _Modèles).
    var customTemplates: [SlashCommand] = []
    /// Fenêtre « Nouvelle page » affichée.
    var newPageRequest: NewPageRequest?
    /// Message bref affiché en bas de la fenêtre (« 3 liens mis à jour »…).
    var toast: String?
    /// Surveillance du dossier (rafraîchissement automatique).
    @ObservationIgnored var watcher: FolderWatcher?
    /// Premier chargement du wiki en cours (écran de démarrage).
    var isLaunching = true
    /// Tous les tags du wiki avec leur nombre de pages (barre latérale, filtres).
    var tagIndex: [TagInfo] = []
    /// Filtres de la recherche Cmd+K : dossier (chemin relatif, vide = tout) et tag (clé normalisée).
    var searchFolderFilter = ""
    var searchTagFilter: String?
    /// Fenêtre du mode examen affichée.
    var isExamPresented = false
    /// Numéro du dernier chargement lancé : un résultat plus ancien arrivé en retard est ignoré.
    @ObservationIgnored var loadGeneration = 0

    /// Largeur minimale de la fenêtre selon les panneaux ouverts (évite que le contenu déborde).
    var requiredMinWidth: CGFloat {
        var width: CGFloat = 760
        if editorMode == .split { width += 220 }
        if peekURL != nil { width += 280 }
        if isOutlinePresented { width += 180 }
        return width
    }

    // MARK: Fenêtres de dialogue

    var prompt: NamePrompt?
    var pendingDelete: WikiNode?
    var errorMessage: String?

    init() {
        editorMode = EditorMode(rawValue: Prefs.string(Prefs.defaultMode, Prefs.Defaults.defaultMode)) ?? .preview
        // Enregistre aussi quand on quitte l'app ou qu'on passe à une autre app.
        let center = NotificationCenter.default
        for name in [NSApplication.willTerminateNotification, NSApplication.willResignActiveNotification] {
            _ = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.save()
            }
        }
        // Reverrouille les pages quand le Mac se met en veille ou que la session est verrouillée.
        startAutoLock()
        // Rouvre le dernier wiki utilisé.
        wikis = FolderAccess.loadList()
        if let id = FolderAccess.currentID ?? wikis.first?.id {
            // Lecture du dossier hors du fil principal : la fenêtre s'affiche tout de suite (écran de démarrage).
            openWiki(id, inBackground: true)
        } else {
            isLaunching = false
        }
    }

    // MARK: Wikis (voir aussi WikiStore+Wikis.swift)

    /// Ouvre un wiki de la liste (le précédent est enregistré et refermé).
    func openWiki(_ id: UUID, inBackground: Bool = false) {
        guard let index = wikis.firstIndex(where: { $0.id == id }) else { isLaunching = false; return }
        var reference = wikis[index]
        guard let url = FolderAccess.resolve(&reference) else {
            isLaunching = false
            errorMessage = "Impossible d'ouvrir « \(reference.name) » : le dossier a été déplacé ou supprimé. Retire-le de la liste puis rouvre-le avec « Ouvrir un wiki existant »."
            return
        }
        wikis[index] = reference
        FolderAccess.saveList(wikis)

        save()
        if let previous = rootURL, previous.standardizedFileURL.path != url.standardizedFileURL.path {
            previous.stopAccessingSecurityScopedResource()
        }
        rootURL = url
        currentWikiID = id
        FolderAccess.currentID = id
        selection = nil
        peekURL = nil
        isSearchPresented = false
        closeFile()
        loadPinned()
        loadWikiSettings()
        if inBackground {
            nodes = []
            searchIndex = []
            WikiAssetSchemeHandler.rootURL = url
            loadInBackground { [weak self] in
                self?.loadCustomTemplates()
                self?.isLaunching = false
            }
        } else {
            reload()
        }
        startWatching()
    }

    /// Ouvrir un wiki existant (Cmd+O).
    func chooseFolder() {
        guard let url = FolderAccess.pickFolder() else { return }
        guard let id = addWiki(url) else { return }
        openWiki(id)
    }

    /// Relit le dossier et la page ouverte depuis le disque (Cmd+R).
    func reload() {
        save()
        guard let rootURL else { nodes = []; searchIndex = []; return }
        loadGeneration += 1 // un chargement en arrière-plan encore en cours est périmé
        apply(Self.snapshot(of: rootURL, previous: indexCache))
        loadCustomTemplates()
        WikiAssetSchemeHandler.rootURL = rootURL
        if let current = selection { selection = node(at: current)?.id }
        if let openURL {
            if FileManager.default.fileExists(atPath: openURL.path) {
                readFile(openURL)
            } else {
                closeFile()
            }
        }
    }

    /// Remplace l'arborescence seulement si elle a changé : la barre latérale n'est pas
    /// redessinée à chaque enregistrement automatique (source du texte dédoublé).
    private func setNodes(_ scanned: [WikiNode]) {
        if scanned != nodes { nodes = scanned }
    }

    // MARK: Chargement (rapide et hors du fil principal)

    /// Arborescence + index, calculés sans toucher à l'interface (utilisable en arrière-plan).
    struct Snapshot {
        let nodes: [WikiNode]
        let index: [SearchEntry]
    }

    static func snapshot(of root: URL, previous: [String: SearchEntry]) -> Snapshot {
        let nodes = WikiScanner.scan(folder: root)
        return Snapshot(nodes: nodes, index: SearchEngine.buildIndex(nodes: nodes, root: root, previous: previous))
    }

    /// Index actuel par chemin : les pages inchangées ne sont pas relues.
    var indexCache: [String: SearchEntry] {
        Dictionary(searchIndex.map { ($0.url.standardizedFileURL.path, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Lit le dossier en arrière-plan, puis applique le résultat sur le fil principal.
    func loadInBackground(then completion: @escaping () -> Void = {}) {
        guard let rootURL else { return completion() }
        loadGeneration += 1
        let generation = loadGeneration
        let previous = indexCache
        DispatchQueue.global(qos: .userInitiated).async {
            let snapshot = WikiStore.snapshot(of: rootURL, previous: previous)
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.loadGeneration, self.rootURL == rootURL else { return }
                self.apply(snapshot)
                completion()
            }
        }
    }

    /// Applique un chargement : ne modifie l'interface que si quelque chose a vraiment changé.
    private func apply(_ snapshot: Snapshot) {
        isLaunching = false // n'importe quel chargement terminé suffit à quitter l'écran de démarrage
        setNodes(snapshot.nodes)
        let unchanged = snapshot.index.count == searchIndex.count
            && zip(snapshot.index, searchIndex).allSatisfy { $0.url == $1.url && $0.modified == $1.modified && $0.title == $1.title }
        if !unchanged {
            searchIndex = snapshot.index
            rebuildPageLookup()
        }
    }

    // MARK: Rafraîchissement automatique

    /// Surveille le dossier : toute modification extérieure (iCloud, Finder, autre éditeur)
    /// rafraîchit l'arborescence, la recherche et la page ouverte.
    func startWatching() {
        watcher = nil
        guard let rootURL else { return }
        watcher = FolderWatcher(url: rootURL) { [weak self] in
            self?.refreshFromDisk()
        }
    }

    /// Comme Cmd+R, mais sans enregistrer et sans écraser une page en cours de modification.
    func refreshFromDisk() {
        guard rootURL != nil else { return }
        // Lecture en arrière-plan : seuls les fichiers modifiés sont relus (en général un seul).
        loadInBackground { [weak self] in self?.finishRefresh() }
    }

    private func finishRefresh() {
        loadCustomTemplates()
        loadWikiSettings()
        if let current = selection { selection = node(at: current)?.id }
        guard let openURL else { return }
        guard FileManager.default.fileExists(atPath: openURL.path) else {
            closeFile()
            return
        }
        // La page a changé sur le disque et tu n'as rien modifié : on recharge.
        if !isDirty, let text = try? String(contentsOf: openURL, encoding: .utf8) {
            let (encrypted, plain) = readablePage(text, at: openURL)
            openPageIsEncrypted = encrypted
            if plain != savedText {
                rawText = plain
                savedText = plain
            }
        }
    }

    // MARK: Page ouverte

    /// Appelé quand la sélection change : enregistre la page quittée, ouvre la nouvelle.
    func openSelection() {
        let target = selectedNode?.pageURL
        if let target, target.standardizedFileURL.path == openURL?.standardizedFileURL.path { return }
        save()
        tocRequest = nil
        if let target, target.standardizedFileURL.path == peekURL?.standardizedFileURL.path {
            peekURL = nil // la page liée devient la page principale
        }
        if let target {
            readFile(target)
            if let node = selectedNode { recordRecent(node.url) }
        } else {
            closeFile()
        }
    }

    func readFile(_ url: URL) {
        saveTask?.cancel()
        openURL = url
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let (encrypted, plain) = readablePage(text, at: url)
            openPageIsEncrypted = encrypted
            rawText = plain
            savedText = plain
            loadError = nil
        } catch {
            openPageIsEncrypted = false
            rawText = ""
            savedText = ""
            loadError = error.localizedDescription
        }
        saveError = nil
    }

    func closeFile() {
        saveTask?.cancel()
        openURL = nil
        openPageIsEncrypted = false
        rawText = ""
        savedText = ""
        loadError = nil
        saveError = nil
    }

    /// Appelé à chaque frappe : on enregistre peu après la dernière modification (Réglages > Éditeur).
    func updateText(_ text: String) {
        guard text != rawText else { return }
        rawText = text
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Prefs.double(Prefs.autosaveDelay, Prefs.Defaults.autosaveDelay)))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    /// Écrit la page sur le disque si elle a été modifiée (Cmd+S force l'enregistrement).
    func save() {
        saveTask?.cancel()
        saveTask = nil
        // Page verrouillée : rawText est vide, surtout ne rien écrire.
        guard let openURL, loadError == nil, isDirty, !isOpenPageLocked else { return }
        do {
            // Page chiffrée et déverrouillée : on rechiffre (nouveau nonce) avant d'écrire.
            var content = rawText
            if openPageIsEncrypted {
                guard let session = lockSessions[Self.lockKey(openURL)] else { return }
                content = try PageCrypto.seal(rawText, with: session)
            }
            // atomically: écrit dans un fichier temporaire puis remplace -> pas de fichier à moitié écrit.
            try content.write(to: openURL, atomically: true, encoding: .utf8)
            savedText = rawText
            saveError = nil
            refreshSearchEntry(for: openURL, text: content)
        } catch {
            saveError = error.localizedDescription
        }
    }

    // MARK: Recherche dans l'arborescence

    var selectedNode: WikiNode? { node(at: selection) }

    func node(at url: URL?) -> WikiNode? {
        guard let path = url?.standardizedFileURL.path else { return nil }
        return find(path, in: nodes)
    }

    /// Enfants directs d'un dossier (la racine comprise).
    func children(of folder: URL) -> [WikiNode] {
        if folder.standardizedFileURL.path == rootURL?.standardizedFileURL.path { return nodes }
        return node(at: folder)?.children ?? []
    }

    /// Fil d'Ariane : "Réseau › Scanning › Nmap".
    func breadcrumb(for node: WikiNode) -> [String] {
        guard let rootURL else { return [node.name] }
        let rootCount = rootURL.standardizedFileURL.pathComponents.count
        let parts = Array(node.url.standardizedFileURL.pathComponents.dropFirst(rootCount))
        return parts.enumerated().map { index, component in
            let isLastFile = index == parts.count - 1 && !node.isFolder
            let raw = isLastFile ? (component as NSString).deletingPathExtension : component
            return WikiScanner.displayName(raw)
        }
    }

    private func find(_ path: String, in list: [WikiNode]) -> WikiNode? {
        for node in list {
            if node.url.standardizedFileURL.path == path { return node }
            if let children = node.children, let found = find(path, in: children) { return found }
        }
        return nil
    }
}
