import Foundation

/// Une variable de page : `vars:` dans l'en-tête, utilisée avec {{NOM}} dans le texte.
struct PageVariable: Identifiable, Equatable {
    let name: String
    let value: String
    var id: String { name }
}

/// Un titre de la page (pour le sommaire).
struct PageHeading: Identifiable {
    let index: Int
    let level: Int
    let title: String
    /// Position (UTF-16) du titre dans le texte complet du fichier.
    let location: Int
    var id: Int { index }
}

/// Une page lue depuis le disque : l'en-tête YAML (front matter) et le corps Markdown.
struct MarkdownPage {
    /// Clés simples de l'en-tête (id, title, notion…).
    let frontMatter: [String: String]
    /// Variables du bloc `vars:`, dans l'ordre du fichier.
    let variables: [PageVariable]
    let body: String

    static func parse(_ text: String) -> MarkdownPage {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")

        // Pas d'en-tête : toute la page est du Markdown.
        guard normalized.hasPrefix("---\n") else {
            return MarkdownPage(frontMatter: [:], variables: [], body: normalized)
        }
        let rest = normalized.dropFirst(4)
        guard let end = rest.range(of: "\n---") else {
            return MarkdownPage(frontMatter: [:], variables: [], body: normalized)
        }

        let yaml = rest[rest.startIndex..<end.lowerBound]
        var body = String(rest[end.upperBound...])
        // Retire la fin de ligne qui suit le "---" de fermeture.
        if let newline = body.firstIndex(of: "\n"),
           body[..<newline].trimmingCharacters(in: .whitespaces).isEmpty {
            body = String(body[body.index(after: newline)...])
        }

        var frontMatter: [String: String] = [:]
        var variables: [PageVariable] = []
        var currentBlock: String?
        for line in yaml.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = unquote(line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
            let isIndented = line.hasPrefix(" ") || line.hasPrefix("\t")

            if isIndented {
                // Ligne d'un bloc (ex. sous "vars:").
                if currentBlock == "vars", !key.isEmpty { variables.append(PageVariable(name: key, value: value)) }
            } else {
                frontMatter[key] = value
                currentBlock = value.isEmpty ? key : nil
            }
        }
        return MarkdownPage(frontMatter: frontMatter, variables: variables, body: body)
    }

    // MARK: YAML

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else { return value }
        return String(value.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"")
    }

    /// Met une valeur entre guillemets si elle contient des caractères spéciaux en YAML.
    static func yamlValue(_ value: String) -> String {
        let special = CharacterSet(charactersIn: ":#'\"[]{},&*!|>%@`")
        guard value.rangeOfCharacter(from: special) != nil
                || value.hasPrefix(" ") || value.hasSuffix(" ") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Remplace la ligne `title:` de l'en-tête (sans toucher au reste de la page).
    static func settingTitle(_ title: String, in text: String) -> String {
        settingField("title", to: title, in: text)
    }

    /// Remplace une ligne `clé: valeur` existante de l'en-tête.
    static func settingField(_ key: String, to value: String, in text: String) -> String {
        guard text.hasPrefix("---\n"),
              let end = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: 4)..<text.endIndex)
        else { return text }
        let header = text[text.startIndex..<end.lowerBound]
        guard let line = header.range(of: "(?m)^\(key):.*$", options: .regularExpression) else { return text }
        var result = text
        result.replaceSubrange(line, with: "\(key): \(yamlValue(value))")
        return result
    }

    /// Nombre de lignes de l'en-tête (pour faire correspondre une ligne de l'éditeur à l'aperçu).
    static func headerLineCount(_ text: String, body: String) -> Int {
        max(text.components(separatedBy: "\n").count - body.components(separatedBy: "\n").count, 0)
    }

    // MARK: Cases à cocher

    private static let taskPattern = try! NSRegularExpression( // swiftlint:disable:this force_try
        pattern: "^((?:\\s*>)*\\s*(?:[-*+]|\\d+\\.)\\s+)\\[([ xX])\\](?=\\s+\\S)"
    )

    /// Coche / décoche la n-ième case « - [ ] » de la page (hors en-tête et hors blocs de code),
    /// dans le même ordre que l'aperçu.
    static func togglingTask(at target: Int, in text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        var inFrontMatter = text.hasPrefix("---\n")
        var inFence = false
        var count = 0
        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if inFrontMatter {
                if index > 0 && trimmed == "---" { inFrontMatter = false }
                continue
            }
            if trimmed.hasPrefix("```") { inFence.toggle(); continue }
            guard !inFence else { continue }
            let ns = lines[index] as NSString
            guard let match = taskPattern.firstMatch(in: lines[index], range: NSRange(location: 0, length: ns.length)) else { continue }
            if count == target {
                let mark = ns.substring(with: match.range(at: 2))
                lines[index] = ns.replacingCharacters(in: match.range(at: 2), with: mark == " " ? "x" : " ")
                return lines.joined(separator: "\n")
            }
            count += 1
        }
        return text
    }

    /// Définit une variable dans le bloc `vars:` de l'en-tête (créé si besoin).
    static func settingVariable(_ name: String, to value: String, in text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        let newLine = "  \(name): \(yamlValue(value))"

        // Pas d'en-tête : on en crée un.
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else {
            return (["---", "vars:", newLine, "---", ""] + lines).joined(separator: "\n")
        }

        if let varsIndex = lines[1..<end].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "vars:" }) {
            var index = varsIndex + 1
            while index < end, lines[index].hasPrefix(" ") || lines[index].hasPrefix("\t") {
                let key = lines[index].split(separator: ":", maxSplits: 1).first?
                    .trimmingCharacters(in: .whitespaces)
                if key == name {
                    lines[index] = newLine
                    return lines.joined(separator: "\n")
                }
                index += 1
            }
            lines.insert(newLine, at: index)
        } else {
            lines.insert(contentsOf: ["vars:", newLine], at: end)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Variables {{NOM}}

    private static let variablePattern = try! NSRegularExpression( // swiftlint:disable:this force_try
        pattern: "\\{\\{\\s*([A-Za-z0-9_]+)\\s*\\}\\}"
    )

    /// Noms des variables utilisées dans le texte, dans l'ordre d'apparition.
    static func usedVariableNames(in body: String) -> [String] {
        let ns = body as NSString
        var names: [String] = []
        for match in variablePattern.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: match.range(at: 1))
            if !names.contains(name) { names.append(name) }
        }
        return names
    }

    /// Remplace {{NOM}} par sa valeur (les variables sans valeur restent visibles telles quelles).
    static func substitute(_ body: String, variables: [PageVariable]) -> String {
        let values = Dictionary(variables.map { ($0.name, $0.value) }, uniquingKeysWith: { first, _ in first })
        guard !values.isEmpty else { return body }
        let ns = body as NSString
        let result = NSMutableString(string: body)
        for match in variablePattern.matches(in: body, range: NSRange(location: 0, length: ns.length)).reversed() {
            let name = ns.substring(with: match.range(at: 1))
            if let value = values[name], !value.isEmpty {
                result.replaceCharacters(in: match.range, with: value)
            }
        }
        return result as String
    }

    // MARK: Sommaire

    /// Titres # de la page (hors en-tête et hors blocs de code), avec leur position dans le texte.
    static func headings(in text: String) -> [PageHeading] {
        var headings: [PageHeading] = []
        var location = 0
        var inFrontMatter = text.hasPrefix("---\n")
        var isFirstLine = true
        var inFence = false

        for line in text.components(separatedBy: "\n") {
            defer {
                location += (line as NSString).length + 1
                isFirstLine = false
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if inFrontMatter {
                if !isFirstLine && trimmed == "---" { inFrontMatter = false }
                continue
            }
            if trimmed.hasPrefix("```") { inFence.toggle(); continue }
            guard !inFence, trimmed.hasPrefix("#") else { continue }

            let level = trimmed.prefix(while: { $0 == "#" }).count
            let rest = trimmed.dropFirst(level)
            guard level <= 6, rest.first == " " else { continue }
            var title = rest.trimmingCharacters(in: .whitespaces)
            while title.hasSuffix("#") { title.removeLast() }
            title = title.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }
            headings.append(PageHeading(index: headings.count, level: level, title: title, location: location))
        }
        return headings
    }
}
