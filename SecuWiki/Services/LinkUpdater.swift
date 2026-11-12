import Foundation

/// Met à jour les liens [[…]] quand une page est renommée.
enum LinkUpdater {
    private static let linkPattern = try! NSRegularExpression( // swiftlint:disable:this force_try
        pattern: "\\[\\[([^\\]|\\n]+)(\\|[^\\]\\n]+)?\\]\\]"
    )

    /// Remplace [[Ancien nom]] et [[Ancien nom|texte]] par [[Nouveau nom]] / [[Nouveau nom|texte]].
    /// Les blocs de code ne sont pas modifiés. Retourne le texte et le nombre de liens remplacés.
    static func replacingLinks(in text: String, oldKeys: Set<String>, newName: String) -> (text: String, count: Int) {
        var lines = text.components(separatedBy: "\n")
        var inFence = false
        var count = 0

        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inFence.toggle()
                continue
            }
            guard !inFence, lines[index].contains("[[") else { continue }

            let ns = lines[index] as NSString
            let result = NSMutableString(string: lines[index])
            let matches = linkPattern.matches(in: lines[index], range: NSRange(location: 0, length: ns.length))
            for match in matches.reversed() {
                let target = SearchEngine.normalize(ns.substring(with: match.range(at: 1)))
                    .trimmingCharacters(in: .whitespaces)
                guard oldKeys.contains(target) else { continue }
                let alias = match.range(at: 2).location != NSNotFound ? ns.substring(with: match.range(at: 2)) : ""
                result.replaceCharacters(in: match.range, with: "[[\(newName)\(alias)]]")
                count += 1
            }
            lines[index] = result as String
        }
        return (lines.joined(separator: "\n"), count)
    }
}
