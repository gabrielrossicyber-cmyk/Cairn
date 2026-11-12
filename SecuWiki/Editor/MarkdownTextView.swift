import AppKit
import SwiftUI

/// Zone de texte de l'éditeur, avec les raccourcis Markdown :
/// - « / » ouvre le menu des commandes (/table, /bash, /lab…) ;
/// - « [[ » propose les pages du wiki pour créer un lien interne ;
/// - Cmd+V d'une capture d'écran ou d'un fichier image : copie dans assets/ + lien ;
/// - Cmd+B gras, Cmd+I italique, Cmd+Maj+C code ;
/// - Tab / Maj+Tab dans un tableau, Entrée dans une liste (MarkdownTextView+Shortcuts.swift).
final class MarkdownTextView: NSTextView {

    /// Fichier de la page ouverte (pour enregistrer les images à côté).
    var documentURL: URL?
    /// Pages du wiki proposées après « [[ ».
    var pageProvider: () -> [WikiLinkTarget] = { [] }
    /// Commandes « / » en plus des commandes intégrées (modèles personnels du dossier _Modèles).
    var extraCommands: () -> [SlashCommand] = { [] }

    // MARK: État du menu de complétion

    private enum MenuKind { case slash, wikiLink }

    private var menuKind: MenuKind = .slash
    private var menuView: NSHostingView<SlashMenuView>?
    private var menuRange: NSRange?
    private var menuQuery = ""
    private var menuItems: [CompletionItem] = []
    private var slashMatches: [SlashCommand] = []
    private var pageMatches: [WikiLinkTarget] = []
    private var selectedIndex = 0
    /// Position d'un déclencheur dont le menu a été fermé avec Échap : on ne le rouvre pas.
    private var suppressedLocation: Int?
    private var updateScheduled = false

    // MARK: Colonne de texte centrée

    /// Largeur maximale du texte : au-delà, des marges apparaissent des deux côtés
    /// (lignes courtes = lecture et écriture plus confortables).
    static let maxColumnWidth: CGFloat = 760

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateColumnInsets()
    }

    func updateColumnInsets() {
        let horizontal = max(28, ((frame.width - Self.maxColumnWidth) / 2).rounded())
        let inset = NSSize(width: horizontal, height: 32)
        if textContainerInset != inset { textContainerInset = inset }
    }

    // MARK: Cycle de vie

    override func didChangeText() {
        super.didChangeText()
        setNeedsSlashMenuUpdate()
    }

    override func resignFirstResponder() -> Bool {
        closeMenu()
        return super.resignFirstResponder()
    }

    /// Met à jour le menu au prochain tour de boucle (jamais pendant une modification du texte).
    func setNeedsSlashMenuUpdate() {
        guard !updateScheduled else { return }
        updateScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.updateScheduled = false
            self?.updateMenu()
        }
    }

    // MARK: Touches spéciales (appelé par le délégué, voir MarkdownEditor)

    /// Retourne `true` si la touche a été gérée ici.
    func handleCommand(_ selector: Selector) -> Bool {
        if menuView != nil {
            updateMenu() // tient compte de la dernière lettre tapée
        }
        if menuView != nil, !menuItems.isEmpty {
            switch selector {
            case #selector(moveUp(_:)):
                selectedIndex = (selectedIndex - 1 + menuItems.count) % menuItems.count
                showMenu()
                return true
            case #selector(moveDown(_:)):
                selectedIndex = (selectedIndex + 1) % menuItems.count
                showMenu()
                return true
            case #selector(insertNewline(_:)), #selector(insertTab(_:)):
                applyMenuItem(at: selectedIndex)
                return true
            case #selector(cancelOperation(_:)), #selector(complete(_:)):
                suppressedLocation = menuRange?.location
                closeMenu()
                return true
            default:
                break
            }
        }

        switch selector {
        case #selector(insertTab(_:)):
            return moveToCell(forward: true)
        case #selector(insertBacktab(_:)):
            return moveToCell(forward: false)
        case #selector(insertNewline(_:)):
            return continueList()
        default:
            return false
        }
    }

    // MARK: Menu de complétion

    func updateMenu() {
        let ns = string as NSString
        if let range = currentSlashRange() {
            guard range.location != suppressedLocation else { closeMenu(); return }
            let query = ns.substring(with: NSRange(location: range.location + 1, length: range.length - 1))
            let found = SlashCommand.matching(query, in: SlashCommand.all + extraCommands())
            guard !found.isEmpty else { closeMenu(); return }
            slashMatches = found
            setMenu(.slash, range: range, query: query, items: found.map {
                CompletionItem(id: $0.trigger, title: $0.title, detail: "/\($0.trigger) · \($0.detail)", icon: $0.icon)
            })
        } else if let range = currentWikiLinkRange() {
            guard range.location != suppressedLocation else { closeMenu(); return }
            let query = ns.substring(with: NSRange(location: range.location + 2, length: range.length - 2))
            let found = matchingPages(query)
            guard !found.isEmpty else { closeMenu(); return }
            pageMatches = found
            setMenu(.wikiLink, range: range, query: query, items: found.enumerated().map { index, page in
                CompletionItem(id: "\(index)-\(page.title)", title: page.title, detail: page.path, icon: "doc.text")
            })
        } else {
            suppressedLocation = nil
            closeMenu()
        }
    }

    private func setMenu(_ kind: MenuKind, range: NSRange, query: String, items: [CompletionItem]) {
        if query != menuQuery || kind != menuKind || menuView == nil { selectedIndex = 0 }
        selectedIndex = min(selectedIndex, items.count - 1)
        menuKind = kind
        menuRange = range
        menuQuery = query
        menuItems = items
        showMenu()
    }

    /// Le « / » en cours de saisie : en début de ligne ou après un espace, suivi de lettres seulement.
    private func currentSlashRange() -> NSRange? {
        let selection = selectedRange()
        guard selection.length == 0, window != nil else { return nil }
        let ns = string as NSString
        let caret = selection.location
        let lineStart = lineContentRange(at: caret).location

        var index = caret
        while index > lineStart {
            let char = ns.character(at: index - 1)
            if char == 0x2F { // "/"
                let slash = index - 1
                if slash > lineStart {
                    guard let previous = UnicodeScalar(ns.character(at: slash - 1)),
                          CharacterSet.whitespaces.contains(previous) else { return nil }
                }
                guard caret - slash <= 20, !isInsideCodeFence(slash) else { return nil }
                return NSRange(location: slash, length: caret - slash)
            }
            guard let scalar = UnicodeScalar(char), CharacterSet.alphanumerics.contains(scalar) else { return nil }
            index -= 1
        }
        return nil
    }

    /// Le « [[ » en cours de saisie (pas encore refermé par « ]] »).
    private func currentWikiLinkRange() -> NSRange? {
        let selection = selectedRange()
        guard selection.length == 0, window != nil else { return nil }
        let ns = string as NSString
        let caret = selection.location
        let line = lineContentRange(at: caret)
        let before = ns.substring(with: NSRange(location: line.location, length: caret - line.location)) as NSString
        let open = before.range(of: "[[", options: .backwards)
        guard open.location != NSNotFound else { return nil }
        let query = before.substring(from: NSMaxRange(open))
        guard !query.contains("]"), (query as NSString).length <= 60 else { return nil }
        let start = line.location + open.location
        guard !isInsideCodeFence(start) else { return nil }
        return NSRange(location: start, length: caret - start)
    }

    private func matchingPages(_ query: String) -> [WikiLinkTarget] {
        let pages = pageProvider()
        let q = SearchEngine.normalize(query).trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            return Array(pages.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }.prefix(30))
        }
        let prefixed = pages.filter { SearchEngine.normalize($0.title).hasPrefix(q) }
        let contained = pages.filter {
            let title = SearchEngine.normalize($0.title)
            return !title.hasPrefix(q) && (title.contains(q) || SearchEngine.normalize($0.path).contains(q))
        }
        return Array((prefixed + contained).prefix(30))
    }

    private func showMenu() {
        guard let range = menuRange, let window else { return }
        let view = SlashMenuView(items: menuItems, selectedIndex: selectedIndex) { [weak self] index in
            self?.applyMenuItem(at: index)
        }

        let menu: NSHostingView<SlashMenuView>
        if let existing = menuView {
            existing.rootView = view
            menu = existing
        } else {
            menu = NSHostingView(rootView: view)
            addSubview(menu)
            menuView = menu
        }

        // Position du déclencheur à l'écran -> dans la zone de texte.
        let size = SlashMenuView.size(for: menuItems.count)
        let screenRect = firstRect(forCharacterRange: NSRange(location: range.location, length: 1), actualRange: nil)
        let caretRect = convert(window.convertFromScreen(screenRect), from: nil)
        var origin = NSPoint(x: caretRect.minX - SlashMenuView.margin, y: caretRect.maxY)
        if origin.y + size.height > visibleRect.maxY {
            origin.y = caretRect.minY - size.height // pas de place en dessous : au-dessus
        }
        origin.x = min(max(origin.x, 0), max(bounds.width - size.width, 0))
        menu.frame = NSRect(origin: origin, size: size)
    }

    private func closeMenu() {
        menuView?.removeFromSuperview()
        menuView = nil
        menuRange = nil
        menuItems = []
    }

    private func applyMenuItem(at index: Int) {
        guard let range = menuRange else { return }
        switch menuKind {
        case .slash:
            guard slashMatches.indices.contains(index) else { return }
            let command = slashMatches[index]
            closeMenu()
            insert(command, replacing: range)
        case .wikiLink:
            guard pageMatches.indices.contains(index) else { return }
            let target = pageMatches[index]
            closeMenu()
            var replaceRange = range
            let ns = string as NSString
            // « ]] » déjà présent après le curseur : on le remplace aussi.
            if NSMaxRange(range) + 2 <= ns.length,
               ns.substring(with: NSRange(location: NSMaxRange(range), length: 2)) == "]]" {
                replaceRange.length += 2
            }
            replace(replaceRange, with: "[[\(target.title)]]", selecting: nil)
        }
        window?.makeFirstResponder(self)
    }

    /// Insère le modèle d'une commande à la place de `range`.
    func insert(_ command: SlashCommand, replacing range: NSRange) {
        var snippet = Snippet(template: command.template())
        if command.isBlock, range.location > lineContentRange(at: range.location).location {
            snippet.prepend("\n") // un bloc commence sur sa propre ligne
        }
        let selection = snippet.selection.map {
            NSRange(location: range.location + $0.location, length: $0.length)
        }
        replace(range, with: snippet.text, selecting: selection)
    }

    // MARK: Coller / glisser une image

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "svg"]
    private static let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]

    /// Sans ça, macOS grise « Coller » quand le presse-papier ne contient qu'une image
    /// (l'éditeur est en texte brut) et Cmd+V ne fait rien.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        super.readablePasteboardTypes + Self.imageTypes
    }

    override func paste(_ sender: Any?) {
        if insertImages(from: NSPasteboard.general) { return }
        super.paste(sender)
    }

    /// Glisser-déposer d'images depuis le Finder : même traitement, à l'endroit du dépôt.
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        if documentURL != nil, !imageFiles(in: pasteboard).isEmpty {
            let point = convert(sender.draggingLocation, from: nil)
            setSelectedRange(NSRange(location: characterIndexForInsertion(at: point), length: 0))
            if insertImages(from: pasteboard) { return true }
        }
        return super.performDragOperation(sender)
    }

    private func imageFiles(in pasteboard: NSPasteboard) -> [URL] {
        let files = pasteboard.readObjects(forClasses: [NSURL.self],
                                           options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return files.filter { Self.imageExtensions.contains($0.pathExtension.lowercased()) }
    }

    /// Capture d'écran ou fichier image -> copie dans `assets/` (à côté de la page) + lien Markdown.
    /// Retourne `false` s'il n'y a pas d'image (collage normal).
    private func insertImages(from pasteboard: NSPasteboard) -> Bool {
        guard let pageURL = documentURL else { return false }
        let folder = pageURL.deletingLastPathComponent()
        let assets = folder.appendingPathComponent("assets", isDirectory: true)
        let pageName = pageURL.lastPathComponent.lowercased() == "index.md"
            ? folder.lastPathComponent
            : pageURL.deletingPathExtension().lastPathComponent
        let baseName = (try? FileNaming.fileName(from: pageName)) ?? "image"
        let fm = FileManager.default
        var links: [String] = []

        do {
            // 1. Fichiers image (copiés ou glissés depuis le Finder).
            for file in imageFiles(in: pasteboard) {
                try fm.createDirectory(at: assets, withIntermediateDirectories: true)
                let name = (try? FileNaming.fileName(from: file.deletingPathExtension().lastPathComponent)) ?? baseName
                let destination = uniqueURL(in: assets, name: name, ext: file.pathExtension.lowercased())
                try fm.copyItem(at: file, to: destination)
                links.append(imageMarkdown(destination))
            }

            // 2. Image brute (capture Cmd+Ctrl+Maj+4, « Copier l'image »…) :
            //    seulement si l'image est le contenu principal du presse-papier (pas du texte).
            if links.isEmpty {
                let firstType = pasteboard.types?.first
                guard let firstType, Self.imageTypes.contains(firstType) || pasteboard.string(forType: .string) == nil,
                      let png = pngData(from: pasteboard) else { return false }
                try fm.createDirectory(at: assets, withIntermediateDirectories: true)
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMdd-HHmmss"
                let destination = uniqueURL(in: assets, name: "\(baseName)-\(formatter.string(from: .now))", ext: "png")
                try png.write(to: destination)
                links.append(imageMarkdown(destination))
            }
        } catch {
            _ = presentError(error)
            return true
        }

        guard !links.isEmpty else { return false }
        replace(selectedRange(), with: links.joined(separator: "\n"), selecting: nil)
        return true
    }

    private func pngData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        if let tiff = pasteboard.data(forType: .tiff), let bitmap = NSBitmapImageRep(data: tiff) {
            return bitmap.representation(using: .png, properties: [:])
        }
        return nil
    }

    private func uniqueURL(in folder: URL, name: String, ext: String) -> URL {
        var candidate = folder.appendingPathComponent(name).appendingPathExtension(ext)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(name)-\(counter)").appendingPathExtension(ext)
            counter += 1
        }
        return candidate
    }

    private func imageMarkdown(_ url: URL) -> String {
        let name = url.lastPathComponent
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        return "![capture](assets/\(encoded))"
    }

    // MARK: Format (menu Format de l'app)

    @objc func markdownBold(_ sender: Any?) { toggleWrap("**") }
    @objc func markdownItalic(_ sender: Any?) { toggleWrap("*") }
    @objc func markdownInlineCode(_ sender: Any?) { toggleWrap("`") }
    @objc func markdownInsertTable(_ sender: Any?) { insertCommand("table") }
    @objc func markdownInsertCode(_ sender: Any?) { insertCommand("bash") }

    /// Envoie une action à l'éditeur actif (s'il y en a un).
    static func perform(_ action: Selector) {
        NSApp.sendAction(action, to: nil, from: nil)
    }

    private func insertCommand(_ trigger: String) {
        guard let command = SlashCommand.all.first(where: { $0.trigger == trigger }) else { return }
        insert(command, replacing: selectedRange())
    }

    /// Entoure la sélection de `marker` (ou retire les marqueurs s'ils sont déjà là).
    private func toggleWrap(_ marker: String) {
        let selection = selectedRange()
        let ns = string as NSString
        let length = (marker as NSString).length

        let hasBefore = selection.location >= length
            && ns.substring(with: NSRange(location: selection.location - length, length: length)) == marker
        let hasAfter = NSMaxRange(selection) + length <= ns.length
            && ns.substring(with: NSRange(location: NSMaxRange(selection), length: length)) == marker

        if hasBefore && hasAfter {
            let outer = NSRange(location: selection.location - length, length: selection.length + 2 * length)
            replace(outer, with: ns.substring(with: selection),
                    selecting: NSRange(location: selection.location - length, length: selection.length))
        } else {
            let inner = ns.substring(with: selection)
            replace(selection, with: marker + inner + marker,
                    selecting: NSRange(location: selection.location + length, length: selection.length))
        }
    }

    // MARK: Outils communs

    /// Remplace du texte en passant par le système d'annulation (Cmd+Z fonctionne).
    func replace(_ range: NSRange, with text: String, selecting selection: NSRange?) {
        guard shouldChangeText(in: range, replacementString: text) else { return }
        textStorage?.replaceCharacters(in: range, with: text)
        didChangeText()
        setSelectedRange(selection ?? NSRange(location: range.location + (text as NSString).length, length: 0))
        scrollRangeToVisible(selectedRange())
    }

    /// Ligne qui contient `location`, sans le retour à la ligne final.
    func lineContentRange(at location: Int) -> NSRange {
        let ns = string as NSString
        var start = 0
        var end = 0
        var contentsEnd = 0
        ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd,
                        for: NSRange(location: min(location, ns.length), length: 0))
        return NSRange(location: start, length: contentsEnd - start)
    }

    /// Vrai si `location` est dans un bloc ``` … ``` (pas de raccourcis dans le code).
    func isInsideCodeFence(_ location: Int) -> Bool {
        let before = (string as NSString).substring(to: min(location, (string as NSString).length))
        var inside = false
        before.enumerateLines { line, _ in
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { inside.toggle() }
        }
        return inside
    }
}
