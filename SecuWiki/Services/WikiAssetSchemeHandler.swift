import Foundation
import WebKit
import UniformTypeIdentifiers

/// Sert les images du wiki à l'aperçu via l'adresse `secuwiki-asset:///chemin/vers/image.png`.
///
/// Pourquoi : l'aperçu (WKWebView) n'a pas le droit de lire tes fichiers directement (sandbox).
/// C'est l'app qui lit l'image et la lui transmet, et seulement si elle est DANS le dossier du wiki
/// (protection contre « ../../ » : path traversal).
final class WikiAssetSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "secuwiki-asset"
    /// Dossier racine du wiki (mis à jour par WikiStore).
    static var rootURL: URL?

    /// Taille maximale servie à l'aperçu (protège la mémoire contre un fichier énorme).
    private static let maximumSize = 300 * 1024 * 1024

    /// Chemin réel du fichier demandé, seulement s'il est DANS le wiki.
    /// « .. » et liens symboliques sont résolus AVANT la vérification (pas d'évasion du dossier).
    static func safeFileURL(for url: URL) -> URL? {
        guard let root = rootURL else { return nil }
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        let fileURL = URL(fileURLWithPath: url.path).standardizedFileURL.resolvingSymlinksInPath()
        guard fileURL.path.hasPrefix(rootPath + "/") else { return nil }
        return fileURL
    }

    /// Documents que l'on peut ouvrir d'un clic. Les applications et scripts ne sont jamais lancés.
    static func isSafeToOpen(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        let blocked: [UTType] = [.application, .applicationBundle, .executable, .script, .shellScript,
                                 .unixExecutable, .package, .systemPreferencesPane, .bundle, .pluginBundle]
        if blocked.contains(where: { type.conforms(to: $0) }) { return false }
        return ["command", "terminal", "tool", "workflow", "scpt", "applescript", "jar", "pkg", "mpkg", "dmg"]
            .contains(url.pathExtension.lowercased()) == false
    }

    /// Type annoncé à l'aperçu. Les pages web et scripts du wiki sont servis comme du texte brut :
    /// affichés tels quels, jamais interprétés (pas de script d'un fichier importé dans l'aperçu).
    static func servedMIMEType(for fileURL: URL) -> String {
        let ext = fileURL.pathExtension.lowercased()
        if ["html", "htm", "xhtml", "xht", "shtml", "js", "mjs", "xml", "xsl", "xslt", "svgz"].contains(ext) {
            return "text/plain"
        }
        return UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        guard let fileURL = Self.safeFileURL(for: url) else {
            urlSchemeTask.didFailWithError(URLError(.noPermissionsToReadFile))
            return
        }
        if let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > Self.maximumSize {
            urlSchemeTask.didFailWithError(URLError(.dataLengthExceedsMaximum))
            return
        }
        do {
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            let mimeType = Self.servedMIMEType(for: fileURL)
            var headers = ["Content-Type": mimeType, "Content-Length": String(data.count)]
            if mimeType == "text/plain" {
                // Le type annoncé ne peut pas être « deviné » autrement par WebKit.
                headers["X-Content-Type-Options"] = "nosniff"
            }
            if mimeType == "image/svg+xml" {
                // Un SVG peut contenir du script : il ne s'exécute jamais et ne contacte pas le réseau.
                headers["Content-Security-Policy"] = "default-src 'none'; style-src 'unsafe-inline'; img-src data:"
            }
            let withHeaders: URLResponse? = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)
            let response = withHeaders
                ?? URLResponse(url: url, mimeType: mimeType, expectedContentLength: data.count, textEncodingName: nil)
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

/// Informations envoyées à l'aperçu en plus du texte.
struct RenderContext: Encodable, Equatable {
    /// Dossier de la page (pour les images relatives).
    var base: String
    /// Noms de pages existants, normalisés (pour colorer les liens [[…]] cassés).
    var pages: [String]
    /// Réglages d'affichage (voir Réglages > Aperçu).
    var fontSize = Prefs.Defaults.previewFontSize
    var maxWidth = Prefs.Defaults.previewMaxWidth
    var breaks = Prefs.Defaults.lineBreaks
    var autoVertical = Prefs.Defaults.autoVerticalDiagrams
    /// PDF : afficher les réponses masquées.
    var printAnswers = Prefs.Defaults.pdfShowAnswers
    /// Cases à cocher cliquables (aperçu principal uniquement).
    var interactiveTasks = false
    /// Noms des secrets présents dans le Trousseau (jamais les valeurs) : « 🔑 NOM » en rouge s'il manque.
    var secretNames: [String] = []
    /// Images hébergées sur Internet : chargées d'office (true) ou seulement au clic (false, par défaut).
    var remoteImages = Prefs.Defaults.remoteImages

    static let empty = RenderContext(base: "", pages: [])

    /// Contexte avec les réglages actuels (utilisé pour l'export PDF).
    static func current(base: String, pages: [String]) -> RenderContext {
        RenderContext(
            base: base,
            pages: pages,
            fontSize: Prefs.double(Prefs.previewFontSize, Prefs.Defaults.previewFontSize),
            maxWidth: Prefs.double(Prefs.previewMaxWidth, Prefs.Defaults.previewMaxWidth),
            breaks: Prefs.bool(Prefs.lineBreaks, Prefs.Defaults.lineBreaks),
            autoVertical: Prefs.bool(Prefs.autoVerticalDiagrams, Prefs.Defaults.autoVerticalDiagrams),
            printAnswers: Prefs.bool(Prefs.pdfShowAnswers, Prefs.Defaults.pdfShowAnswers),
            remoteImages: Prefs.bool(Prefs.remoteImages, Prefs.Defaults.remoteImages)
        )
    }
}
