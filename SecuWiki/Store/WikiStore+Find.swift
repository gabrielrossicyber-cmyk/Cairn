import AppKit

/// Recherche dans la page (Cmd+F) et ouverture d'un résultat de Cmd+K à l'endroit du texte.
///
/// - Lecture et côte à côte : barre de recherche de Cairn, résultats surlignés dans l'aperçu.
/// - Édition : barre de recherche native de l'éditeur de texte (avec remplacement).
extension WikiStore {

    // MARK: Cmd+F, Cmd+G

    /// L'éditeur de texte de la fenêtre (nil en mode Lecture).
    private static func editorTextView() -> NSTextView? {
        func search(_ view: NSView?) -> NSTextView? {
            guard let view else { return nil }
            if let editor = view as? MarkdownTextView { return editor }
            for subview in view.subviews {
                if let found = search(subview) { return found }
            }
            return nil
        }
        return search((NSApp.keyWindow ?? NSApp.mainWindow)?.contentView)
    }

    /// Vrai si le curseur est dans l'éditeur (et pas dans un champ de saisie comme la barre de recherche).
    private static func editorHasFocus() -> Bool {
        guard let responder = (NSApp.keyWindow ?? NSApp.mainWindow)?.firstResponder as? NSTextView else { return false }
        return responder is MarkdownTextView
    }

    /// La recherche passe par l'éditeur natif : mode Édition, ou côte à côte avec le curseur dans l'éditeur.
    private var usesEditorFind: Bool {
        editorMode == .edit || (editorMode == .split && Self.editorHasFocus())
    }

    private func sendToEditor(_ action: NSTextFinder.Action) {
        guard let editor = Self.editorTextView() else { return }
        if editor.window?.firstResponder !== editor { editor.window?.makeFirstResponder(editor) }
        let item = NSMenuItem()
        item.tag = action.rawValue
        editor.performTextFinderAction(item)
    }

    var canFindInPage: Bool {
        openURL != nil && !isOpenPageLocked && loadError == nil && !isLinkMapPresented
    }

    /// Cmd+F.
    func findInPage() {
        guard canFindInPage else { return }
        if usesEditorFind { return sendToEditor(.showFindInterface) }
        isFindPresented = true
        findFocusToken += 1
        if !findQuery.isEmpty { runFind() }
    }

    /// Cmd+G / Maj+Cmd+G.
    func findStep(forward: Bool) {
        guard canFindInPage else { return }
        if usesEditorFind { return sendToEditor(forward ? .nextMatch : .previousMatch) }
        guard isFindPresented, !findQuery.isEmpty else { return findInPage() }
        findRequest = FindRequest(kind: forward ? .next : .previous)
    }

    /// Lance (ou relance) la recherche du texte de la barre dans l'aperçu.
    func runFind(line: Int? = nil, automatic: Bool = false) {
        let query = findQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            findCount = 0
            findIndex = 0
            findRequest = FindRequest(kind: .clear)
            return
        }
        findRequest = FindRequest(kind: .search, query: query, line: line, isAutomatic: automatic)
    }

    func closeFind() {
        guard isFindPresented || findRequest != nil else { return }
        isFindPresented = false
        findCount = 0
        findIndex = 0
        findRequest = FindRequest(kind: .clear)
        KeyboardNavigator.shared.focusPage() // le clavier revient à la page (↑↓ font défiler)
    }

    /// Changement de page : la recherche de la page précédente ne s'applique plus.
    func resetFind() {
        isFindPresented = false
        findCount = 0
        findIndex = 0
        findRequest = nil
        editorJump = nil
    }

    /// Réponse de l'aperçu : nombre de résultats et position du résultat courant (à partir de 1).
    func findResult(count: Int, index: Int) {
        findCount = count
        findIndex = index
        // Ouverture depuis Cmd+K sans aucun résultat dans le texte (tag de l'en-tête, mot du titre…) : pas de barre.
        if count == 0, findRequest?.isAutomatic == true {
            isFindPresented = false
            findRequest = FindRequest(kind: .clear)
        }
    }

    // MARK: Ouvrir un résultat de Cmd+K à l'endroit du texte

    /// Ouvre la page puis se place sur le texte cherché (`line` : ligne du corps de la page, si connue).
    func openPage(_ url: URL, jumpingTo query: String, line: Int?) {
        let path = url.standardizedFileURL.path
        if path == openURL?.standardizedFileURL.path {
            jumpToMatch(of: query, line: line)
            return
        }
        pendingJump = PendingJump(path: path, query: query, line: line)
        openPage(url)
    }

    /// Appelé dès que la page demandée est chargée.
    func applyPendingJump(for url: URL) {
        guard let jump = pendingJump else { return }
        pendingJump = nil
        guard jump.path == url.standardizedFileURL.path else { return }
        jumpToMatch(of: jump.query, line: jump.line)
    }

    private func jumpToMatch(of query: String, line: Int?) {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, !isOpenPageLocked, loadError == nil else { return }
        isLinkMapPresented = false // la carte des liens cache la page

        // Éditeur : le passage est sélectionné et amené à l'écran.
        if editorMode != .preview, let range = MarkdownPage.matchRange(of: query, nearBodyLine: line, in: rawText) {
            editorJump = EditorJump(range: range, takesFocus: editorMode == .edit)
        }
        // Aperçu : tous les résultats sont surlignés, la barre permet de passer de l'un à l'autre.
        if editorMode != .edit {
            findQuery = query
            isFindPresented = true
            runFind(line: line, automatic: true)
        }
    }
}
