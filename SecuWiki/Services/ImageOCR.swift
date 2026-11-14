import CryptoKit
import Foundation
import ImageIO
import Vision

/// Texte des images des pages (captures d'écran de cours, schémas…) pour la recherche Cmd+K.
///
/// - Reconnaissance **locale** avec Vision (rien n'est envoyé sur Internet), en français et en anglais.
/// - Faite en arrière-plan, une image à la fois ; le résultat est gardé en cache (dossier Caches de l'app,
///   hors du wiki et d'iCloud) et recalculé seulement si l'image change.
/// - Le cache ne garde que les images encore utilisées par une page non verrouillée.
final class ImageOCR {
    static let shared = ImageOCR()

    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "gif", "tif", "tiff", "webp", "bmp"]
    /// Au-delà, l'image est ignorée (trop lourde pour valoir la peine).
    private static let maximumFileSize = 40 * 1024 * 1024

    private struct Item: Codable {
        var modified: Date
        var text: String
    }

    private let lock = NSLock()
    private var items: [String: Item] = [:]
    private var pending: [URL] = []
    private var queued = Set<String>()
    private var isRunning = false
    private var cacheURL: URL?
    private let queue = DispatchQueue(label: "ch.gabriel.cairn.ocr", qos: .utility)

    /// Appelé sur le fil principal avec les chemins des images qui viennent d'être lues.
    var onRecognized: ((Set<String>) -> Void)?

    static var isEnabled: Bool { Prefs.bool(Prefs.ocrEnabled, Prefs.Defaults.ocrEnabled) }

    // MARK: Cache

    /// Charge le cache du wiki ouvert.
    func open(root: URL) {
        let digest = SHA256.hash(data: Data(root.standardizedFileURL.path.utf8))
            .prefix(8).map { String(format: "%02x", $0) }.joined()
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cairn-OCR", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(digest + ".json")
        let loaded = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([String: Item].self, from: $0) } ?? [:]
        lock.lock()
        cacheURL = url
        items = loaded
        pending.removeAll()
        queued.removeAll()
        lock.unlock()
    }

    /// Texte déjà reconnu pour cette image (nil si pas encore lue ou modifiée depuis). Utilisable depuis n'importe quel fil.
    func cachedText(for url: URL) -> String? {
        let path = url.standardizedFileURL.path
        guard let modified = Self.modificationDate(of: url) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard let item = items[path], item.modified == modified else { return nil }
        return item.text
    }

    /// Oublie les images qui ne sont plus utilisées (ou dont la page a été verrouillée).
    func prune(keeping paths: Set<String>) {
        lock.lock()
        let before = items.count
        items = items.filter { paths.contains($0.key) }
        let changed = items.count != before
        lock.unlock()
        if changed { queue.async { self.save() } }
    }

    private func save() {
        lock.lock()
        let snapshot = items
        let url = cacheURL
        lock.unlock()
        guard let url, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: Reconnaissance

    /// Ajoute des images à lire (en arrière-plan, sans bloquer l'app).
    func enqueue(_ urls: [URL]) {
        guard Self.isEnabled else { return }
        lock.lock()
        for url in urls where queued.insert(url.standardizedFileURL.path).inserted {
            pending.append(url)
        }
        let shouldStart = !isRunning && !pending.isEmpty
        if shouldStart { isRunning = true }
        lock.unlock()
        if shouldStart { queue.async { self.processQueue() } }
    }

    private func processQueue() {
        var recognized = Set<String>()
        while true {
            lock.lock()
            guard !pending.isEmpty else {
                isRunning = false
                lock.unlock()
                break
            }
            let url = pending.removeFirst()
            lock.unlock()

            let path = url.standardizedFileURL.path
            guard let modified = Self.modificationDate(of: url) else { continue }
            let text = autoreleasepool { Self.recognizeText(in: url) } ?? ""
            lock.lock()
            items[path] = Item(modified: modified, text: text)
            queued.remove(path)
            lock.unlock()
            if !text.isEmpty { recognized.insert(path) }

            // Résultats envoyés par paquets : la recherche s'enrichit au fur et à mesure.
            if recognized.count >= 8 {
                deliver(recognized)
                recognized.removeAll()
            }
        }
        deliver(recognized)
    }

    private func deliver(_ paths: Set<String>) {
        save()
        guard !paths.isEmpty else { return }
        DispatchQueue.main.async { self.onRecognized?(paths) }
    }

    /// Texte de l'image, ligne par ligne (Vision, précision maximale, correction linguistique).
    static func recognizeText(in url: URL) -> String? {
        if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > maximumFileSize { return nil }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["fr-FR", "en-US"]
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            return nil
        }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }

    private static func modificationDate(of url: URL) -> Date? {
        var fresh = url
        fresh.removeAllCachedResourceValues()
        return (try? fresh.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}

extension MarkdownPage {
    private static let markdownImagePattern = try! NSRegularExpression( // swiftlint:disable:this force_try
        pattern: "!\\[[^\\]]*\\]\\(<?([^)>\\s]+)>?(?:\\s+\"[^\"]*\")?\\)"
    )
    private static let embedImagePattern = try! NSRegularExpression( // swiftlint:disable:this force_try
        pattern: "!\\[\\[([^\\]|\\n]+)(?:\\|[^\\]\\n]*)?\\]\\]"
    )

    /// Images locales utilisées par la page (![](assets/x.png) et ![[assets/x.png]]), dans le wiki uniquement.
    static func imageReferences(in body: String, page: URL, root: URL) -> [URL] {
        let ns = body as NSString
        let range = NSRange(location: 0, length: ns.length)
        let folder = page.deletingLastPathComponent()
        let rootPath = root.standardizedFileURL.path + "/"
        var result: [URL] = []
        var seen = Set<String>()
        for pattern in [markdownImagePattern, embedImagePattern] {
            for match in pattern.matches(in: body, range: range) {
                let raw = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
                guard !raw.contains("://"), !raw.hasPrefix("data:") else { continue }
                let decoded = raw.removingPercentEncoding ?? raw
                let url = folder.appendingPathComponent(decoded).standardizedFileURL
                guard url.path.hasPrefix(rootPath),
                      ImageOCR.imageExtensions.contains(url.pathExtension.lowercased()),
                      seen.insert(url.path).inserted,
                      FileManager.default.fileExists(atPath: url.path) else { continue }
                result.append(url)
            }
        }
        return result
    }
}
