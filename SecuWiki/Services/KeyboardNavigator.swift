import AppKit
import WebKit

/// Navigation au clavier dans la fenêtre principale, sans souris.
///
/// - Tab / Maj+Tab : passe d'une zone à l'autre (arborescence → éditeur → aperçu → arborescence).
///   Dans l'éditeur, Tab sert à l'indentation et aux tableaux : c'est ⌃Tab / ⌃⇧Tab qui change de zone.
/// - Arborescence : ↑↓ pour changer de page (natif), → / ← pour déplier / replier un dossier (natif),
///   ↩ pour entrer dans la page.
/// - Aperçu : ↑↓, Espace, ⇞⇟ font défiler la page (natif dès que l'aperçu a le clavier).
@MainActor
final class KeyboardNavigator {
    static let shared = KeyboardNavigator()

    private weak var store: WikiStore?
    private var monitor: Any?

    /// Les zones dans l'ordre de passage, avec leur vue.
    enum Zone: Equatable {
        case sidebar(NSTableView)
        case editor(NSTextView)
        case preview(WKWebView)

        var view: NSView {
            switch self {
            case .sidebar(let view): view
            case .editor(let view): view
            case .preview(let view): view
            }
        }
    }

    func install(store: WikiStore) {
        self.store = store
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) ?? event }
        }
    }

    // MARK: Touches

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let store, let window = event.window, window.isKeyWindow, window.attachedSheet == nil,
              !store.isSearchPresented, !store.isExamPresented else { return event }
        let zones = zones(in: window)
        guard !zones.isEmpty else { return event } // pas la fenêtre principale (Réglages, capture rapide…)

        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let current = zoneIndex(of: window.firstResponder, in: zones)

        switch Int(event.keyCode) {
        case 48: // Tab
            guard flags.isDisjoint(with: [.command, .option]) else { return event }
            let withControl = flags.contains(.control)
            if !withControl {
                // Éditeur : Tab indente ; champ de saisie (recherche dans la page, variables) : champ suivant.
                if let current, case .editor = zones[current] { return event }
                if current == nil, window.firstResponder is NSText { return event }
            }
            move(by: flags.contains(.shift) ? -1 : 1, from: current, in: zones, window: window)
            return nil

        case 36, 76: // Retour, Entrée du pavé numérique
            guard flags.isEmpty, let current, case .sidebar = zones[current], store.openURL != nil,
                  let page = zones.first(where: { if case .sidebar = $0 { false } else { true } }) else { return event }
            focus(page, in: window)
            return nil

        default:
            return event
        }
    }

    // MARK: Zones

    /// Zones visibles de la fenêtre, de gauche à droite (l'arborescence d'abord).
    func zones(in window: NSWindow) -> [Zone] {
        guard let root = window.contentView else { return [] }
        var tables: [NSTableView] = []
        var editors: [NSTextView] = []
        var previews: [WKWebView] = []
        func walk(_ view: NSView) {
            if view.isHidden { return }
            if let web = view as? WKWebView {
                previews.append(web)
                return // rien d'utile à l'intérieur
            }
            if let editor = view as? MarkdownTextView {
                editors.append(editor)
            } else if let table = view as? NSTableView {
                tables.append(table)
            }
            view.subviews.forEach(walk)
        }
        walk(root)

        func minX(_ view: NSView) -> CGFloat { view.convert(view.bounds, to: nil).minX }
        func isVisible(_ view: NSView) -> Bool { view.visibleRect.width > 1 && view.visibleRect.height > 1 }

        // L'arborescence est la liste la plus à gauche (le sommaire, à droite, est aussi une liste).
        guard let sidebar = tables.filter(isVisible).min(by: { minX($0) < minX($1) }) else { return [] }
        let page = (editors.filter(isVisible).map { Zone.editor($0) } + previews.filter(isVisible).map { Zone.preview($0) })
            .sorted { minX($0.view) < minX($1.view) }
        return [.sidebar(sidebar)] + page
    }

    private func zoneIndex(of responder: NSResponder?, in zones: [Zone]) -> Int? {
        guard let view = responder as? NSView else { return nil }
        return zones.firstIndex { view === $0.view || view.isDescendant(of: $0.view) }
    }

    private func move(by step: Int, from current: Int?, in zones: [Zone], window: NSWindow) {
        let index: Int
        if let current {
            index = (current + step + zones.count) % zones.count
        } else {
            index = 0 // nulle part (après une fenêtre, un clic dans la barre d'outils…) : l'arborescence
        }
        focus(zones[index], in: window)
    }

    private func focus(_ zone: Zone, in window: NSWindow) {
        window.makeFirstResponder(zone.view)
        if case .editor(let editor) = zone {
            editor.scrollRangeToVisible(editor.selectedRange())
        }
    }

    // MARK: Actions des menus

    /// Menu Aller › Zone suivante / précédente (⌃Tab).
    func cycle(forward: Bool) {
        guard store?.isSearchPresented != true, let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        let zones = zones(in: window)
        guard !zones.isEmpty else { return }
        move(by: forward ? 1 : -1, from: zoneIndex(of: window.firstResponder, in: zones), in: zones, window: window)
    }

    /// Donne le clavier à l'arborescence (démarrage, fermeture de la recherche).
    func focusSidebar(onlyIfIdle: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
            if onlyIfIdle, window.firstResponder is NSView, window.firstResponder !== window.contentView { return }
            if let sidebar = self.zones(in: window).first { self.focus(sidebar, in: window) }
        }
    }

    /// Donne le clavier à la page (après avoir ouvert un résultat de recherche) : ↑↓ font défiler.
    func focusPage() {
        // La page vient peut-être d'être ouverte : on laisse SwiftUI l'afficher d'abord.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
            let zones = self.zones(in: window)
            guard let page = zones.dropFirst().first else { return }
            // Côte à côte : on garde l'éditeur s'il a été choisi (le texte trouvé y est sélectionné).
            let target = self.store?.editorMode == .preview ? zones.last ?? page : page
            self.focus(target, in: window)
        }
    }
}
