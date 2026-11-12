import Foundation

/// Opérations sur les fichiers et dossiers du wiki.
/// Règle commune : on enregistre la page ouverte AVANT de toucher au disque.
extension WikiStore {

    // MARK: Demandes venant de l'interface (ouvrent une fenêtre de saisie)

    /// Ouvre la fenêtre « Nouvelle page » (titre + choix du modèle).
    func requestNewPage(near node: WikiNode? = nil) {
        guard let folder = targetFolder(for: node ?? selectedNode) else { return }
        newPageRequest = NewPageRequest(folder: folder)
    }

    func requestNewFolder(near node: WikiNode? = nil) {
        guard let folder = targetFolder(for: node ?? selectedNode) else { return }
        prompt = NamePrompt(action: .newFolder(in: folder))
    }

    func requestRename(_ node: WikiNode? = nil) {
        guard let node = node ?? selectedNode else { return }
        prompt = NamePrompt(action: .rename(node))
    }

    func requestDelete(_ node: WikiNode? = nil) {
        pendingDelete = node ?? selectedNode
    }

    func perform(_ prompt: NamePrompt, name: String) {
        switch prompt.action {
        case .newPage(let folder): createPage(titled: name, in: folder, template: wikiSettings.defaultTemplate)
        case .newFolder(let folder): createFolder(named: name, in: folder)
        case .rename(let node): rename(node, to: name)
        }
    }

    /// Où créer un nouvel élément : dans le dossier sélectionné, à côté de la page sélectionnée, ou à la racine.
    func targetFolder(for node: WikiNode?) -> URL? {
        guard let rootURL else { return nil }
        guard let node else { return rootURL }
        return node.isFolder ? node.url : node.url.deletingLastPathComponent()
    }

    // MARK: Créer

    /// `template` : déclencheur d'un modèle (« lab », « cours »…), vide = page vide.
    func createPage(titled title: String, in folder: URL, template: String = "") {
        attempt {
            let fileName = try FileNaming.fileName(from: title)
            let url = folder.appendingPathComponent(fileName).appendingPathExtension("md")
            guard !FileManager.default.fileExists(atPath: url.path) else {
                throw WikiError("Une page porte déjà ce nom à cet endroit.")
            }
            save()
            try PageTemplate.newPage(title: title.trimmingCharacters(in: .whitespaces), body: templateBody(template))
                .write(to: url, atomically: true, encoding: .utf8)
            OrderFile.append(WikiNode.orderKey(for: url, isFolder: false), in: folder)
            editorMode = .split
            select(url)
        }
    }

    func createFolder(named name: String, in folder: URL) {
        attempt {
            let folderName = try FileNaming.fileName(from: name)
            let url = folder.appendingPathComponent(folderName, isDirectory: true)
            guard !FileManager.default.fileExists(atPath: url.path) else {
                throw WikiError("Un élément porte déjà ce nom à cet endroit.")
            }
            save()
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            OrderFile.append(WikiNode.orderKey(for: url, isFolder: true), in: folder)
            select(url)
        }
    }

    /// Crée le fichier index.md d'un dossier (la page qui s'affiche quand on clique dessus).
    func createIndexPage(for folder: WikiNode) {
        attempt {
            let url = folder.url.appendingPathComponent("index.md")
            guard !FileManager.default.fileExists(atPath: url.path) else { return }
            save()
            try PageTemplate.newPage(title: folder.name, body: defaultTemplateBody)
                .write(to: url, atomically: true, encoding: .utf8)
            editorMode = .split
            select(folder.url)
        }
    }

    // MARK: Renommer

    func rename(_ node: WikiNode, to title: String) {
        attempt {
            let parent = node.url.deletingLastPathComponent()
            let baseName = try FileNaming.fileName(from: title)
            var newURL = parent.appendingPathComponent(baseName, isDirectory: node.isFolder)
            if !node.isFolder { newURL.appendPathExtension("md") }

            let oldPath = node.url.standardizedFileURL.path
            let newPath = newURL.standardizedFileURL.path
            guard oldPath != newPath else { return }

            save()
            // Noms sous lesquels les autres pages font un lien vers celle-ci (avant renommage).
            let pagePath = node.pageURL?.standardizedFileURL.path
            let oldKeys = Set(searchIndex.first { $0.url.standardizedFileURL.path == pagePath }?.keys ?? [])

            let fm = FileManager.default
            if oldPath.lowercased() == newPath.lowercased() {
                // Seule la casse change (nmap -> Nmap) : macOS ne distingue pas, on passe par un nom temporaire.
                let temp = parent.appendingPathComponent(UUID().uuidString)
                try fm.moveItem(at: node.url, to: temp)
                try fm.moveItem(at: temp, to: newURL)
            } else {
                guard !fm.fileExists(atPath: newPath) else {
                    throw WikiError("Un élément porte déjà ce nom à cet endroit.")
                }
                try fm.moveItem(at: node.url, to: newURL)
            }

            OrderFile.rename(node.orderKey, to: WikiNode.orderKey(for: newURL, isFolder: node.isFolder), in: parent)
            if !node.isFolder { try updateTitle(of: newURL, to: title.trimmingCharacters(in: .whitespaces)) }
            remapOpenURL(from: node.url, to: newURL)
            remapPinned(from: node.url, to: newURL)
            peekURL = nil

            // Les liens [[Ancien nom]] des autres pages pointent vers le nouveau nom.
            let newName = node.isFolder
                ? WikiScanner.displayName(newURL.lastPathComponent)
                : title.trimmingCharacters(in: .whitespaces)
            let updated = updateLinks(from: oldKeys, to: newName, movedFrom: node.url, to: newURL)
            select(newURL)
            if updated > 0 {
                showToast(updated == 1 ? "1 lien mis à jour" : "\(updated) liens mis à jour")
            }
        }
    }

    // MARK: Dupliquer

    /// Copie une page (« Nom-copie.md », nouvel id, titre « … (copie) ») ou un dossier entier.
    func duplicate(_ node: WikiNode) {
        attempt {
            save()
            let fm = FileManager.default
            let parent = node.url.deletingLastPathComponent()
            let base = node.isFolder ? node.url.lastPathComponent : node.url.deletingPathExtension().lastPathComponent

            var copy: URL
            var number = 1
            repeat {
                let suffix = number == 1 ? "-copie" : "-copie-\(number)"
                copy = node.isFolder
                    ? parent.appendingPathComponent(base + suffix, isDirectory: true)
                    : parent.appendingPathComponent(base + suffix).appendingPathExtension("md")
                number += 1
            } while fm.fileExists(atPath: copy.path)

            try fm.copyItem(at: node.url, to: copy)
            if !node.isFolder {
                var text = try String(contentsOf: copy, encoding: .utf8)
                let title = (MarkdownPage.parse(text).frontMatter["title"] ?? node.name) + " (copie)"
                text = MarkdownPage.settingTitle(title, in: text)
                text = MarkdownPage.settingField("id", to: UUID().uuidString.lowercased(), in: text)
                try text.write(to: copy, atomically: true, encoding: .utf8)
            }
            OrderFile.append(WikiNode.orderKey(for: copy, isFolder: node.isFolder), in: parent)
            select(copy)
            showToast("« \(node.name) » dupliqué")
        }
    }

    // MARK: Déplacer et réordonner

    func move(_ node: WikiNode, to folder: URL) {
        attempt {
            let source = node.url.standardizedFileURL.path
            let destinationFolder = folder.standardizedFileURL.path
            let parent = node.url.deletingLastPathComponent()

            guard parent.standardizedFileURL.path != destinationFolder else { return }
            guard destinationFolder != source, !destinationFolder.hasPrefix(source + "/") else {
                throw WikiError("Impossible de déplacer un dossier dans lui-même.")
            }
            let destination = folder.appendingPathComponent(node.url.lastPathComponent, isDirectory: node.isFolder)
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                throw WikiError("« \(node.name) » existe déjà dans ce dossier.")
            }

            save()
            try FileManager.default.moveItem(at: node.url, to: destination)
            OrderFile.remove(node.orderKey, in: parent)
            OrderFile.append(node.orderKey, in: folder)
            remapOpenURL(from: node.url, to: destination)
            remapPinned(from: node.url, to: destination)
            peekURL = nil
            select(destination)
        }
    }

    /// Monte (-1) ou descend (+1) un élément parmi ses voisins, en écrivant le fichier `.order`.
    func reorder(_ node: WikiNode, by offset: Int) {
        attempt {
            let parent = node.url.deletingLastPathComponent()
            var keys = children(of: parent).map(\.orderKey)
            guard let index = keys.firstIndex(of: node.orderKey) else { return }
            let target = index + offset
            guard keys.indices.contains(target) else { return }
            keys.swapAt(index, target)
            try OrderFile.write(keys, in: parent)
            reload()
        }
    }

    /// Liste des dossiers pour le menu « Déplacer vers » (sans l'élément lui-même ni ses sous-dossiers).
    func folderOptions(excluding node: WikiNode) -> [FolderOption] {
        guard let rootURL else { return [] }
        var options = [FolderOption(url: rootURL, label: "Racine")]
        let excluded = node.url.standardizedFileURL.path

        func walk(_ list: [WikiNode], prefix: String) {
            for item in list where item.isFolder {
                if item.url.standardizedFileURL.path == excluded { continue }
                let label = prefix.isEmpty ? item.name : "\(prefix) › \(item.name)"
                options.append(FolderOption(url: item.url, label: label))
                walk(item.children ?? [], prefix: label)
            }
        }
        walk(nodes, prefix: "")
        return options
    }

    // MARK: Couleur d'un dossier

    /// Écrit (ou retire) le fichier caché `.color` du dossier.
    func setColor(_ color: FolderColor?, for node: WikiNode) {
        guard node.isFolder else { return }
        let file = node.url.appendingPathComponent(FolderColor.fileName)
        do {
            if let color {
                try color.rawValue.write(to: file, atomically: true, encoding: .utf8)
            } else if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
            reload()
        } catch {
            errorMessage = "Impossible de changer la couleur du dossier : \(error.localizedDescription)"
        }
    }

    // MARK: Supprimer

    /// Met à la corbeille (récupérable), jamais de suppression définitive.
    func delete(_ node: WikiNode) {
        attempt {
            save()
            let target = node.url.standardizedFileURL.path
            if let open = openURL?.standardizedFileURL.path, open == target || open.hasPrefix(target + "/") {
                closeFile()
            }
            try FileManager.default.trashItem(at: node.url, resultingItemURL: nil)
            OrderFile.remove(node.orderKey, in: node.url.deletingLastPathComponent())
            removePinned(under: node.url)
            peekURL = nil
            selection = nil
            reload()
        }
    }

    // MARK: Outils internes

    /// Exécute une opération et affiche l'erreur éventuelle dans une alerte.
    private func attempt(_ work: () throws -> Void) {
        do {
            try work()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Relit l'arborescence puis sélectionne et ouvre l'élément donné.
    private func select(_ url: URL) {
        reload()
        selection = node(at: url)?.id
        openSelection()
    }

    /// Si la page ouverte (ou son dossier) a changé de chemin, on suit le nouveau chemin.
    private func remapOpenURL(from old: URL, to new: URL) {
        guard let open = openURL?.standardizedFileURL.path else { return }
        let oldPath = old.standardizedFileURL.path
        if open == oldPath {
            openURL = new
        } else if open.hasPrefix(oldPath + "/") {
            openURL = URL(fileURLWithPath: new.standardizedFileURL.path + String(open.dropFirst(oldPath.count)))
        }
    }

    /// Remplace les liens vers une page renommée dans tout le wiki. Retourne le nombre de liens modifiés.
    private func updateLinks(from oldKeys: Set<String>, to newName: String, movedFrom old: URL, to new: URL) -> Int {
        guard !oldKeys.isEmpty, !oldKeys.contains(SearchEngine.normalize(newName)) else { return 0 }
        let oldPath = old.standardizedFileURL.path
        var total = 0
        for entry in searchIndex where !oldKeys.isDisjoint(with: entry.links) {
            // Une page située dans le dossier renommé a elle aussi changé de chemin.
            var url = entry.url
            let path = url.standardizedFileURL.path
            if path == oldPath || path.hasPrefix(oldPath + "/") {
                url = URL(fileURLWithPath: new.standardizedFileURL.path + String(path.dropFirst(oldPath.count)))
            }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let result = LinkUpdater.replacingLinks(in: text, oldKeys: oldKeys, newName: newName)
            guard result.count > 0 else { continue }
            if (try? result.text.write(to: url, atomically: true, encoding: .utf8)) != nil {
                total += result.count
            }
        }
        return total
    }

    private func updateTitle(of url: URL, to title: String) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        let updated = MarkdownPage.settingTitle(title, in: text)
        if updated != text { try updated.write(to: url, atomically: true, encoding: .utf8) }
    }
}
