import AppKit
import WebKit

/// Export PDF et impression d'une page.
///
/// Principe : une WKWebView invisible charge le même rendu que l'aperçu (preview.html),
/// puis le système d'impression de macOS la met en pages A4 (règles @media print de preview.css).
final class PDFExporter: NSObject, WKNavigationDelegate {
    enum Mode {
        case pdf(URL)
        case print
    }

    private var webView: WKWebView?
    private var markdown = ""
    private var context = RenderContext.empty
    private var mode: Mode = .print
    private var onFinish: ((String?) -> Void)?

    /// `onFinish` reçoit un message d'erreur, ou `nil` si tout s'est bien passé.
    func run(markdown: String, context: RenderContext, mode: Mode, onFinish: @escaping (String?) -> Void) {
        self.markdown = markdown
        self.context = context
        self.mode = mode
        self.onFinish = onFinish

        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(WikiAssetSchemeHandler(), forURLScheme: WikiAssetSchemeHandler.scheme)
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 760, height: 1000), configuration: configuration)
        webView.navigationDelegate = self
        // PDF et impression toujours en clair, même si l'app est en mode sombre.
        webView.appearance = NSAppearance(named: .aqua)
        self.webView = webView

        guard let html = Bundle.main.url(forResource: "preview", withExtension: "html") else {
            finish("Fichier preview.html introuvable dans l'app.")
            return
        }
        webView.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // « await » : on attend aussi que les schémas Mermaid soient dessinés.
        webView.callAsyncJavaScript(
            "await window.renderMarkdown(source, true, context);",
            arguments: ["source": markdown, "context": contextObject()],
            in: nil,
            in: .page
        ) { [weak self] _ in
            // Petit délai : laisse WebKit terminer la mise en page (images) avant l'impression.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.startPrinting() }
        }
    }

    /// Le contexte converti en objet JavaScript.
    private func contextObject() -> Any {
        guard let data = try? JSONEncoder().encode(context),
              let object = try? JSONSerialization.jsonObject(with: data) else { return [String: Any]() }
        return object
    }

    private func startPrinting() {
        guard let webView,
              let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first else {
            finish("Aucune fenêtre disponible pour l'export.")
            return
        }

        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        // Format du papier (Réglages > Export) : A4 ou Letter, en points.
        info.paperSize = Prefs.string(Prefs.pdfPaper, Prefs.Defaults.pdfPaper) == "Letter"
            ? NSSize(width: 612, height: 792)
            : NSSize(width: 595, height: 842)
        info.topMargin = 40
        info.bottomMargin = 40
        info.leftMargin = 40
        info.rightMargin = 40
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false

        if case .pdf(let url) = mode {
            info.jobDisposition = .save
            info.dictionary().setObject(url, forKey: NSPrintInfo.AttributeKey.jobSavingURL.rawValue as NSString)
        }

        let operation = webView.printOperation(with: info)
        operation.view?.frame = webView.bounds // sans cette ligne, WebKit imprime une page blanche
        if case .pdf = mode {
            operation.showsPrintPanel = false
            operation.showsProgressPanel = false
        } else {
            operation.showsPrintPanel = true
            operation.showsProgressPanel = true
        }

        operation.runModal(
            for: window,
            delegate: self,
            didRun: #selector(printOperationDidRun(_:success:contextInfo:)),
            contextInfo: nil
        )
    }

    @objc private func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        if case .pdf = mode, !success {
            finish("L'export PDF a échoué.")
        } else {
            finish(nil) // impression annulée par l'utilisateur : pas une erreur
        }
    }

    private func finish(_ error: String?) {
        let callback = onFinish
        onFinish = nil
        webView = nil
        callback?(error)
    }
}
