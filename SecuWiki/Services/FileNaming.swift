import Foundation

/// Transforme un titre en nom de fichier : "Lab Nmap : scan SYN" -> "Lab-Nmap-scan-SYN".
enum FileNaming {
    static func fileName(from title: String) throws -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|")
        var name = title.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: forbidden).joined()
            .replacingOccurrences(of: " ", with: "-")
        while name.contains("--") { name = name.replacingOccurrences(of: "--", with: "-") }
        while name.hasPrefix(".") { name.removeFirst() } // pas de fichier caché
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        guard !name.isEmpty else { throw WikiError("Ce nom n'est pas valide.") }
        return name.precomposedStringWithCanonicalMapping
    }
}

/// Contenu d'une nouvelle page (en-tête YAML + titre + modèle par défaut éventuel).
enum PageTemplate {
    /// En-tête YAML seul (id, titre, dates), suivi d'une ligne vide.
    static func header(title: String) -> String {
        let today = Date.now.formatted(.iso8601.year().month().day())
        return "---\nid: \(UUID().uuidString.lowercased())\ntitle: \(MarkdownPage.yamlValue(title))\ncreated: \(today)\nupdated: \(today)\n---\n\n"
    }

    static func newPage(title: String, body: String = "") -> String {
        let today = Date.now.formatted(.iso8601.year().month().day())
        return """
        ---
        id: \(UUID().uuidString.lowercased())
        title: \(MarkdownPage.yamlValue(title))
        created: \(today)
        updated: \(today)
        ---

        # \(title)

        \(body)

        """
    }
}
