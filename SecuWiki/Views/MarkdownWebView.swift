import SwiftUI
import WebKit
import AppKit

/// Demande de défilement vers un titre (clic dans le sommaire).
struct TOCRequest: Equatable {
    let id = UUID()
    let index: Int
    let title: String
    /// Position du titre dans le texte (pour l'éditeur).
    let location: Int
}

/// Défilement synchronisé (mode côte à côte) : l'éditeur signale la ligne affichée en haut,
/// l'aperçu fait défiler jusqu'au bloc correspondant. Volontairement hors SwiftUI : rien n'est redessiné.
final class ScrollSync {
    weak var webView: WKWebView?
    /// Lignes de l'en-tête YAML (absentes de l'aperçu).
    var headerLines = 0
    var isEnabled = false
    private var lastLine = -1.0

    func editorScrolled(toLine line: Double) {
        guard isEnabled, let webView else { return }
        let target = max(line - Double(headerLines), 0)
        guard abs(target - lastLine) > 0.002 else { return } // rien n'a bougé : pas d'appel JS
        lastLine = target
        webView.evaluateJavaScript("window.scrollToLine(\(String(format: "%.3f", target)));")
    }
}

/// Rendu Markdown dans une WKWebView.
///
/// La page `preview.html` (dans le bundle) charge markdown-it, highlight.js et Mermaid en local,
/// sans aucun appel réseau. Swift lui envoie le texte via `window.renderMarkdown(...)`.
struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    /// Change quand on ouvre une autre page : l'aperçu revient alors en haut.
    /// Sinon (frappe en mode côte à côte), la position de défilement est conservée.
    let pageID: URL?
    var context: RenderContext = .empty
    var tocRequest: TOCRequest?
    /// Clic sur un lien [[Page]].
    var onWikiLink: (String) -> Void = { _ in }
    /// Clic sur un #tag.
    var onTag: (String) -> Void = { _ in }
    /// Clic sur une case à cocher (n° de la case dans la page).
    var onToggleTask: (Int) -> Void = { _ in }
    /// Défilement synchronisé avec l'éditeur (mode côte à côte).
    var scrollSync: ScrollSync?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Le bouton « Copier » des blocs de code envoie le texte à Swift (presse-papier natif).
        configuration.userContentController.add(context.coordinator, name: "copy")
        // Les cases à cocher cliquées dans l'aperçu.
        configuration.userContentController.add(context.coordinator, name: "task")
        // Les images du wiki passent par l'app (voir WikiAssetSchemeHandler).
        configuration.setURLSchemeHandler(WikiAssetSchemeHandler(), forURLScheme: WikiAssetSchemeHandler.scheme)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        // Pas d'éclair blanc au chargement en mode sombre.
        webView.underPageBackgroundColor = .textBackgroundColor
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        scrollSync?.webView = webView

        if let html = Bundle.main.url(forResource: "preview", withExtension: "html") {
            webView.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onWikiLink = onWikiLink
        context.coordinator.onTag = onTag
        context.coordinator.onToggleTask = onToggleTask
        scrollSync?.webView = webView
        context.coordinator.render(markdown, pageID: pageID, context: self.context)
        context.coordinator.scroll(to: tocRequest)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "copy")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "task")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var onWikiLink: (String) -> Void = { _ in }
        var onTag: (String) -> Void = { _ in }
        var onToggleTask: (Int) -> Void = { _ in }
        private var isLoaded = false
        private var pending: (markdown: String, pageID: URL?, context: RenderContext)?
        private var lastMarkdown: String?
        private var lastContext: RenderContext?
        private var lastPageID: URL?
        private var pendingTOC: TOCRequest?
        private var lastTOCID: UUID?

        private var debounce: DispatchWorkItem?

        /// Changement de page : rendu immédiat. Frappe dans la même page : regroupé (120 ms),
        /// pour ne pas reconstruire tout l'aperçu à chaque touche.
        func render(_ markdown: String, pageID: URL?, context: RenderContext) {
            pending = (markdown, pageID, context)
            debounce?.cancel()
            let isTyping = isLoaded && pageID == lastPageID && context == lastContext && markdown != lastMarkdown
            guard isTyping else { return flush() }
            let item = DispatchWorkItem { [weak self] in self?.flush() }
            debounce = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
        }

        func scroll(to request: TOCRequest?) {
            guard let request, request.id != lastTOCID else { return }
            pendingTOC = request
            flush()
        }

        /// Envoie le Markdown à la page dès qu'elle est prête (et seulement s'il a changé).
        private func flush() {
            guard isLoaded, let webView else { return }

            if let next = pending {
                pending = nil
                let resetScroll = next.pageID != lastPageID
                if resetScroll || next.markdown != lastMarkdown || next.context != lastContext,
                   let source = json(next.markdown), let context = json(next.context) {
                    lastMarkdown = next.markdown
                    lastContext = next.context
                    lastPageID = next.pageID
                    webView.evaluateJavaScript("window.renderMarkdown(\(source), \(resetScroll), \(context));")
                }
            }

            if let request = pendingTOC, let title = json(request.title) {
                pendingTOC = nil
                lastTOCID = request.id
                webView.evaluateJavaScript("window.scrollToHeading(\(request.index), \(title));")
            }
        }

        /// JSONEncoder transforme une valeur en texte JavaScript correctement échappé.
        private func json<T: Encodable>(_ value: T) -> String? {
            guard let data = try? JSONEncoder().encode(value) else { return nil }
            return String(data: data, encoding: .utf8)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            flush()
        }

        /// Politique de navigation (liste blanche) :
        /// - la page d'aperçu de l'app, et les PDF du wiki affichés dans un cadre ;
        /// - clic sur [[Page]] : ouvert dans l'app ; lien web / mail / Notion : app par défaut ;
        /// - tout le reste (redirection, formulaire, schéma inconnu…) est bloqué.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else { return decisionHandler(.cancel) }
            let scheme = url.scheme?.lowercased() ?? ""
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true

            if navigationAction.navigationType != .linkActivated {
                let isPreviewPage = url.isFileURL && isMainFrame
                    && url.standardizedFileURL.path == Bundle.main.url(forResource: "preview", withExtension: "html")?.standardizedFileURL.path
                let isEmbeddedAsset = scheme == WikiAssetSchemeHandler.scheme && !isMainFrame
                let isBlankFrame = url.absoluteString == "about:blank" && !isMainFrame
                decisionHandler(isPreviewPage || isEmbeddedAsset || isBlankFrame ? .allow : .cancel)
                return
            }

            if scheme == "secuwiki",
               let name = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "name" })?.value {
                onWikiLink(name)
            } else if scheme == "secuwiki-tag",
                      let name = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "name" })?.value {
                onTag(name)
            } else if scheme == WikiAssetSchemeHandler.scheme {
                // « Ouvrir le PDF dans Aperçu » : seulement un document DU wiki, jamais une app ou un script.
                if let file = WikiAssetSchemeHandler.safeFileURL(for: url), WikiAssetSchemeHandler.isSafeToOpen(file) {
                    NSWorkspace.shared.open(file)
                } else if let file = WikiAssetSchemeHandler.safeFileURL(for: url) {
                    NSWorkspace.shared.activateFileViewerSelecting([file]) // type exécutable : montré dans le Finder, pas lancé
                }
            } else if ["http", "https", "mailto", "notion"].contains(scheme) {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            // Messages venant de la page : types et bornes vérifiés avant tout usage.
            // Un document affiché dans un cadre (PDF intégré…) n'a pas le droit d'en envoyer.
            guard message.frameInfo.isMainFrame else { return }
            if message.name == "task", let index = message.body as? Int, (0..<100_000).contains(index) {
                onToggleTask(index)
                return
            }
            guard message.name == "copy", let text = message.body as? String, text.utf16.count <= 5_000_000 else { return }
            // {{secret:NOM}} -> valeur du Trousseau, seulement dans le presse-papiers (effacé après 60 s).
            SecretStore.copyResolving(text)
        }
    }
}
