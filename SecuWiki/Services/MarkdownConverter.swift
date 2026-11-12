import AppKit

/// Convertit un document mis en forme (Word, RTF, HTML, OpenDocument) en Markdown.
///
/// macOS sait lire ces formats en « texte enrichi » (NSAttributedString) ; on en déduit :
/// titres (police plus grande), listes, gras, italique, liens. Les tableaux et images
/// des documents Word ne sont pas repris (le texte des cellules l'est).
enum MarkdownConverter {

    static func markdown(from document: NSAttributedString) -> String {
        let ns = document.string as NSString
        let bodySize = mostCommonFontSize(in: document)
        var lines: [String] = []

        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byParagraphs) { paragraph, range, _, _ in
            guard let paragraph else { return }
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, range.length > 0 else {
                lines.append("")
                return
            }

            let attributes = document.attributes(at: range.location, effectiveRange: nil)
            let font = attributes[.font] as? NSFont
            let style = attributes[.paragraphStyle] as? NSParagraphStyle

            // Liste à puces ou numérotée
            if let lists = style?.textLists, let list = lists.last {
                let indent = String(repeating: "  ", count: max(lists.count - 1, 0))
                let format = list.markerFormat.rawValue.lowercased()
                let ordered = format.contains("decimal") || format.contains("alpha") || format.contains("roman")
                let text = stripListMarker(inline(document, range: range))
                lines.append(indent + (ordered ? "1. " : "- ") + text)
                return
            }

            // Titre : police nettement plus grande que le texte courant
            if let size = font?.pointSize, bodySize > 0 {
                let ratio = size / bodySize
                let isBold = font.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } ?? false
                var level = 0
                if ratio >= 1.6 { level = 1 }
                else if ratio >= 1.3 { level = 2 }
                else if ratio >= 1.1 && isBold { level = 3 }
                if level > 0 && trimmed.count < 120 {
                    lines.append("")
                    lines.append(String(repeating: "#", count: level) + " " + trimmed)
                    lines.append("")
                    return
                }
            }

            lines.append(inline(document, range: range).trimmingCharacters(in: .whitespaces))
            lines.append("")
        }

        // Pas plus d'une ligne vide d'affilée.
        var result: [String] = []
        for line in lines {
            if line.isEmpty && (result.last?.isEmpty ?? true) { continue }
            result.append(line)
        }
        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    /// Texte d'un paragraphe avec **gras**, *italique* et [liens](url).
    private static func inline(_ document: NSAttributedString, range: NSRange) -> String {
        var output = ""
        document.enumerateAttributes(in: range, options: []) { attributes, runRange, _ in
            var text = (document.string as NSString).substring(with: runRange)
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\u{2028}", with: " ")
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
                output += text
                return
            }
            // Les espaces restent hors des marqueurs (« **mot** » et non « ** mot** »).
            let leading = String(text.prefix(while: { $0 == " " }))
            let trailing = String(text.reversed().prefix(while: { $0 == " " }))
            text = text.trimmingCharacters(in: .whitespaces)

            if let font = attributes[.font] as? NSFont {
                let traits = NSFontManager.shared.traits(of: font)
                if traits.contains(.boldFontMask) && traits.contains(.italicFontMask) {
                    text = "***\(text)***"
                } else if traits.contains(.boldFontMask) {
                    text = "**\(text)**"
                } else if traits.contains(.italicFontMask) {
                    text = "*\(text)*"
                }
            }
            if let link = attributes[.link] {
                let target = (link as? URL)?.absoluteString ?? (link as? String) ?? ""
                if !target.isEmpty { text = "[\(text)](\(target))" }
            }
            output += leading + text + trailing
        }
        return output
    }

    /// Retire la puce ou le numéro déjà présents dans le texte (« •\tTexte », « 1.\tTexte »).
    private static func stripListMarker(_ text: String) -> String {
        let pattern = "^\\s*(?:[•◦▪▫‣⁃·\\-–*]|\\d+[.)]|[a-zA-Z][.)]|[ivxIVX]+[.)])\\s+"
        guard let range = text.range(of: pattern, options: .regularExpression) else {
            return text.trimmingCharacters(in: .whitespaces)
        }
        return String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
    }

    /// Taille de police la plus utilisée = texte courant (sert à repérer les titres).
    private static func mostCommonFontSize(in document: NSAttributedString) -> CGFloat {
        var counts: [CGFloat: Int] = [:]
        document.enumerateAttribute(.font, in: NSRange(location: 0, length: document.length), options: []) { value, range, _ in
            guard let font = value as? NSFont else { return }
            counts[font.pointSize, default: 0] += range.length
        }
        return counts.max { $0.value < $1.value }?.key ?? 12
    }
}
