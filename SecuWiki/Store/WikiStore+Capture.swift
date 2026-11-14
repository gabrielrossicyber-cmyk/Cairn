import Foundation

/// Capture rapide : une note tapée en quelques secondes, rangée dans « Boîte de réception ».
extension WikiStore {
    static let inboxFolderName = "Boîte-de-réception"

    /// Crée la page et retourne son titre. La page ouverte et la sélection ne changent pas.
    @discardableResult
    func saveQuickCapture(_ text: String) throws -> String {
        guard let rootURL else { throw WikiError("Aucun wiki ouvert : ouvre Cairn et choisis un wiki.") }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw WikiError("La capture est vide.") }

        // 1re ligne courte = titre ; sinon « Capture 14.11.2026 11h52 ».
        var lines = trimmed.components(separatedBy: "\n")
        let first = lines[0].trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        let stamp = Date.now.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().hour().minute()
            .locale(Locale(identifier: "fr_CH")))
        let title: String
        if !first.isEmpty, first.count <= 70 {
            title = first
            lines.removeFirst()
        } else {
            title = "Capture \(stamp)"
        }
        let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        let fm = FileManager.default
        let inbox = rootURL.appendingPathComponent(Self.inboxFolderName, isDirectory: true)
        if !fm.fileExists(atPath: inbox.path) {
            try fm.createDirectory(at: inbox, withIntermediateDirectories: false)
            try? "gray".write(to: inbox.appendingPathComponent(FolderColor.fileName), atomically: true, encoding: .utf8)
            OrderFile.append(WikiNode.orderKey(for: inbox, isFolder: true), in: rootURL)
        }

        let base = try FileNaming.fileName(from: title)
        var url = inbox.appendingPathComponent(base).appendingPathExtension("md")
        var counter = 2
        while fm.fileExists(atPath: url.path) {
            url = inbox.appendingPathComponent("\(base)-\(counter)").appendingPathExtension("md")
            counter += 1
        }
        let content = PageTemplate.newPage(title: title, body: body + "\n\n_Capturé le \(stamp)._\n")
        try content.write(to: url, atomically: true, encoding: .utf8)
        OrderFile.append(WikiNode.orderKey(for: url, isFolder: false), in: inbox)
        reload()
        return title
    }
}
