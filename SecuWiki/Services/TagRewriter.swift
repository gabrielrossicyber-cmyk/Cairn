import Foundation

/// Réécrit un tag dans le texte d'une page (renommer, fusionner, retirer).
///
/// - En-tête : `tags: a, b` ou liste `- a` (réécrite en `tags: a, b`), doublons fusionnés.
/// - Texte : `#ancien` -> `#nouveau` (hors blocs de code et code en ligne).
///   Si le nouveau nom contient des espaces (impossible en #tag), le mot reste sans « # »
///   et le tag est ajouté à l'en-tête. Retirer un tag garde le mot, sans « # ».
enum TagRewriter {

    static func rewrite(_ key: String, to newName: String?, in text: String) -> String {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var needsHeaderTag = false
        let newKey = newName.map(SearchEngine.normalize)

        // 1. En-tête
        var closeIndex: Int?
        var tagsLineIndex: Int?
        if lines.first == "---",
           let close = lines.indices.dropFirst().first(where: { lines[$0].trimmingCharacters(in: .whitespaces) == "---" }) {
            var header: [String] = []
            var index = 1
            while index < close {
                let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
                guard trimmed.lowercased().hasPrefix("tags:") else {
                    header.append(lines[index])
                    index += 1
                    continue
                }
                var items: [String] = []
                let inline = trimmed.dropFirst(5)
                if inline.trimmingCharacters(in: .whitespaces).isEmpty {
                    // Liste « - tag » sur les lignes suivantes
                    index += 1
                    while index < close, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("-") {
                        items.append(clean(lines[index].trimmingCharacters(in: .whitespaces).dropFirst()))
                        index += 1
                    }
                } else {
                    items = inline.split(separator: ",").map(clean)
                    index += 1
                }
                let rewritten = dedupe(items.filter { !$0.isEmpty }.compactMap {
                    SearchEngine.normalize($0) == key ? newName : $0
                })
                if !rewritten.isEmpty {
                    tagsLineIndex = header.count + 1
                    header.append("tags: " + rewritten.joined(separator: ", "))
                }
            }
            lines = ["---"] + header + Array(lines[close...])
            closeIndex = header.count + 1
        }

        // 2. #tags dans le texte
        let bodyStart = closeIndex.map { $0 + 1 } ?? 0
        var inFence = false
        for index in bodyStart..<lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { inFence.toggle(); continue }
            guard !inFence, line.contains("#") else { continue }
            // Segments pairs = hors `code en ligne`
            var segments = line.components(separatedBy: "`")
            for segment in stride(from: 0, to: segments.count, by: 2) {
                let part = segments[segment] as NSString
                let result = NSMutableString(string: segments[segment])
                let matches = MarkdownPage.inlineTagPattern.matches(in: segments[segment], range: NSRange(location: 0, length: part.length))
                for match in matches.reversed() {
                    let word = part.substring(with: match.range(at: 1))
                    guard SearchEngine.normalize(word) == key else { continue }
                    let replacement: String
                    if let newName, !newName.contains(where: \.isWhitespace) {
                        replacement = "#" + newName
                    } else {
                        replacement = word
                        if newName != nil { needsHeaderTag = true }
                    }
                    result.replaceCharacters(in: match.range, with: replacement)
                }
                segments[segment] = result as String
            }
            lines[index] = segments.joined(separator: "`")
        }

        // 3. Nouveau nom avec espaces : il doit figurer dans l'en-tête
        if needsHeaderTag, let newName, let newKey {
            if let tagsLineIndex {
                let existing = lines[tagsLineIndex].dropFirst(5).split(separator: ",").map(clean)
                if !existing.contains(where: { SearchEngine.normalize($0) == newKey }) {
                    lines[tagsLineIndex] = "tags: " + (existing + [newName]).joined(separator: ", ")
                }
            } else if let closeIndex {
                lines.insert("tags: " + newName, at: closeIndex)
            } else {
                lines.insert(contentsOf: ["---", "tags: " + newName, "---", ""], at: 0)
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func clean<S: StringProtocol>(_ raw: S) -> String {
        raw.trimmingCharacters(in: CharacterSet(charactersIn: " \t#\"'[]"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func dedupe(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert(SearchEngine.normalize($0)).inserted }
    }
}
