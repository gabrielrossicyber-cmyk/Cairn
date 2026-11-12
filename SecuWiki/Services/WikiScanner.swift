import Foundation

/// Parcourt le dossier racine et construit l'arborescence du wiki.
///
/// Règles (voir le cahier des charges, section 5) :
/// - un dossier = une section ; s'il contient `index.md`, ce fichier est sa page ;
/// - un fichier `.md` = une page ;
/// - les dossiers `assets` et les fichiers cachés sont ignorés ;
/// - un fichier `.order` (une ligne par nom, sans `.md`) impose l'ordre d'affichage,
///   le reste est trié par nom (01-, 02-… fonctionnent donc aussi).
enum WikiScanner {
    private static let ignoredFolders: Set<String> = ["assets"]

    static func scan(folder: URL, isRoot: Bool = true) -> [WikiNode] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var nodes: [WikiNode] = []
        for item in items {
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

            if isDirectory {
                if ignoredFolders.contains(item.lastPathComponent.lowercased()) { continue }
                let children = scan(folder: item, isRoot: false)
                let index = item.appendingPathComponent("index.md")
                nodes.append(WikiNode(
                    id: item,
                    name: displayName(item.lastPathComponent),
                    isFolder: true,
                    children: children.isEmpty ? nil : children,
                    pageURL: fm.fileExists(atPath: index.path) ? index : nil,
                    color: FolderColor.read(in: item)
                ))
            } else if item.pathExtension.lowercased() == "md" {
                // Dans un sous-dossier, index.md est la page du dossier : on ne le liste pas.
                if !isRoot && item.lastPathComponent.lowercased() == "index.md" { continue }
                nodes.append(WikiNode(
                    id: item,
                    name: displayName(item.deletingPathExtension().lastPathComponent),
                    isFolder: false,
                    children: nil,
                    pageURL: item
                ))
            }
        }
        return sort(nodes, in: folder)
    }

    /// "Lab-Wireshark-TCP" -> "Lab Wireshark TCP" (convention du wiki Azure DevOps).
    static func displayName(_ raw: String) -> String {
        raw.replacingOccurrences(of: "-", with: " ")
    }

    private static func sort(_ nodes: [WikiNode], in folder: URL) -> [WikiNode] {
        let order = OrderFile.read(in: folder) ?? []
        return nodes.sorted { a, b in
            let ia = order.firstIndex(of: a.orderKey) ?? Int.max
            let ib = order.firstIndex(of: b.orderKey) ?? Int.max
            if ia != ib { return ia < ib }
            return a.orderKey.localizedStandardCompare(b.orderKey) == .orderedAscending
        }
    }
}
