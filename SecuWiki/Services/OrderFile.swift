import Foundation

/// Lecture et écriture du fichier caché `.order` d'un dossier
/// (une ligne par élément, dans l'ordre d'affichage — comme le wiki Azure DevOps).
///
/// Si un dossier n'a pas de `.order`, l'ordre est alphabétique. Le fichier est créé
/// dès que tu réordonnes manuellement (Monter / Descendre).
enum OrderFile {
    static func url(in folder: URL) -> URL {
        folder.appendingPathComponent(".order")
    }

    /// `nil` si le dossier n'a pas de fichier `.order`.
    static func read(in folder: URL) -> [String]? {
        guard let text = try? String(contentsOf: url(in: folder), encoding: .utf8) else { return nil }
        return text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces).precomposedStringWithCanonicalMapping }
            .filter { !$0.isEmpty }
    }

    static func write(_ keys: [String], in folder: URL) throws {
        let text = keys.joined(separator: "\n") + "\n"
        try text.write(to: url(in: folder), atomically: true, encoding: .utf8)
    }

    /// Ajoute un élément en fin de liste (seulement si le dossier a déjà un `.order`).
    static func append(_ key: String, in folder: URL) {
        guard var keys = read(in: folder), !keys.contains(key) else { return }
        keys.append(key)
        try? write(keys, in: folder)
    }

    static func remove(_ key: String, in folder: URL) {
        guard var keys = read(in: folder), keys.contains(key) else { return }
        keys.removeAll { $0 == key }
        try? write(keys, in: folder)
    }

    static func rename(_ oldKey: String, to newKey: String, in folder: URL) {
        guard var keys = read(in: folder), let index = keys.firstIndex(of: oldKey) else { return }
        keys[index] = newKey
        try? write(keys, in: folder)
    }
}
