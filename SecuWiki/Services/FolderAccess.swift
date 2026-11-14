import AppKit

/// Un wiki connu de l'app (un dossier). Plusieurs wikis possibles : brevet, Lemon Flow, perso…
struct WikiReference: Identifiable, Codable, Equatable {
    let id: UUID
    /// Signet à portée de sécurité : permet de rouvrir le dossier sans redemander l'accès.
    var bookmark: Data
    var path: String
    /// Nom affiché (celui des réglages du wiki, sinon le nom du dossier).
    var name: String
}

/// Gère l'accès aux dossiers des wikis depuis la sandbox macOS.
///
/// La sandbox interdit à l'app de lire tes fichiers, sauf ceux que tu choisis toi-même.
/// Pour retrouver un dossier au prochain lancement sans redemander, on enregistre un
/// « signet à portée de sécurité » (security-scoped bookmark) dans les préférences de l'app.
enum FolderAccess {
    private static let listKey = "wikis"
    private static let currentKey = "currentWiki"
    /// Ancienne version (un seul wiki) : repris automatiquement dans la liste.
    private static let legacyKey = "rootFolderBookmark"

    // MARK: Sélecteurs

    /// Choisir un dossier existant (wiki déjà créé, ou dossier de notes à transformer en wiki).
    static func pickFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Ouvrir"
        panel.message = "Choisis le dossier d'un wiki existant."
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// Choisir l'emplacement et le nom d'un nouveau wiki (un nouveau dossier sera créé).
    static func pickNewWikiLocation() -> URL? {
        let panel = NSSavePanel()
        panel.title = "Nouveau wiki"
        panel.prompt = "Créer"
        panel.nameFieldLabel = "Nom du wiki :"
        panel.nameFieldStringValue = "Mon wiki"
        panel.message = "Un dossier portant ce nom sera créé. Conseil : place-le dans iCloud Drive."
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    // MARK: Signets

    static func reference(for url: URL, name: String) -> WikiReference? {
        guard let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return nil }
        return WikiReference(id: UUID(), bookmark: data, path: url.standardizedFileURL.path, name: name)
    }

    /// Ouvre l'accès au dossier d'un wiki. Met à jour le signet s'il est périmé.
    static func resolve(_ reference: inout WikiReference) -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: reference.bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        if isStale, let data = try? url.bookmarkData(options: .withSecurityScope,
                                                     includingResourceValuesForKeys: nil,
                                                     relativeTo: nil) {
            reference.bookmark = data
        }
        reference.path = url.standardizedFileURL.path
        return url
    }

    /// Le dossier n'existe plus, ou se trouve dans une corbeille (un signet suit le dossier jusque-là).
    static func isUnavailable(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return true
        }
        return isInTrash(url.standardizedFileURL.path)
    }

    /// Corbeille du compte (~/.Trash), d'un disque externe (.Trashes) ou d'iCloud Drive (.Trash).
    static func isInTrash(_ path: String) -> Bool {
        path.components(separatedBy: "/").contains { $0 == ".Trash" || $0 == ".Trashes" }
    }

    // MARK: Liste des wikis

    static func loadList() -> [WikiReference] {
        if let data = UserDefaults.standard.data(forKey: listKey),
           let list = try? JSONDecoder().decode([WikiReference].self, from: data) {
            return list
        }
        // Migration depuis la version à un seul wiki.
        guard let legacy = UserDefaults.standard.data(forKey: legacyKey) else { return [] }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: legacy, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &isStale) else { return [] }
        let reference = WikiReference(id: UUID(), bookmark: legacy, path: url.standardizedFileURL.path,
                                      name: url.lastPathComponent)
        saveList([reference])
        currentID = reference.id
        return [reference]
    }

    static func saveList(_ list: [WikiReference]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: listKey)
        }
    }

    /// Dernier wiki ouvert (rouvert au lancement).
    static var currentID: UUID? {
        get { UserDefaults.standard.string(forKey: currentKey).flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: currentKey) }
    }
}
