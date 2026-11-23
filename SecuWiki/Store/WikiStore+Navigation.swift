import Foundation

/// Historique de navigation (page précédente / suivante) et passage d'une page à l'autre de l'arborescence.
extension WikiStore {

    // MARK: Historique

    /// Appelé à chaque page ouverte (sauf pendant un retour en arrière ou en avant).
    func recordHistory(_ id: URL) {
        // Page atteinte par Retour / Avancer : l'historique ne change pas (la page s'ouvre juste après).
        if let pending = pendingHistoryTarget {
            pendingHistoryTarget = nil
            if pending == id { return }
        }
        if historyIndex >= 0, historyIndex < history.count, history[historyIndex] == id { return }
        if historyIndex < history.count - 1 { history.removeSubrange((historyIndex + 1)...) }
        history.append(id)
        if history.count > 100 { history.removeFirst(history.count - 100) }
        historyIndex = history.count - 1
    }

    var canGoBack: Bool { previousHistoryIndex(step: -1) != nil }
    var canGoForward: Bool { previousHistoryIndex(step: 1) != nil }

    /// Prochaine entrée de l'historique qui existe encore (une page supprimée est sautée).
    private func previousHistoryIndex(step: Int) -> Int? {
        var index = historyIndex + step
        while index >= 0, index < history.count {
            if node(at: history[index]) != nil, history[index] != selection { return index }
            index += step
        }
        return nil
    }

    func goBack() { navigateHistory(step: -1) }
    func goForward() { navigateHistory(step: 1) }

    private func navigateHistory(step: Int) {
        guard let index = previousHistoryIndex(step: step) else { return }
        historyIndex = index
        pendingHistoryTarget = history[index]
        selection = history[index]
    }

    // MARK: Page suivante / précédente dans l'arborescence

    var canGoToAdjacentPage: Bool { !pageOrder.isEmpty }

    /// Page suivante (ou précédente) dans l'ordre de l'arborescence, dossiers repliés compris.
    func goToAdjacentPage(forward: Bool) {
        guard !pageOrder.isEmpty else { return }
        guard let current = selection, let index = pageOrder.firstIndex(of: current) else {
            selection = forward ? pageOrder.first : pageOrder.last
            return
        }
        let next = index + (forward ? 1 : -1)
        guard pageOrder.indices.contains(next) else { return }
        selection = pageOrder[next]
    }
}
