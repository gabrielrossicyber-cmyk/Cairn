import AppKit

/// Coloration sobre du Markdown dans l'éditeur : la structure se lit par la taille et la graisse
/// (titres plus grands), la couleur est réservée à ce qui doit ressortir (liens, code, variables).
enum MarkdownHighlighter {
    /// Taille de la police (Réglages > Éditeur), mise à jour par MarkdownEditor.
    static var fontSize: CGFloat = 13

    static var baseFont: NSFont { NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular) }
    static var boldFont: NSFont { NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold) }
    /// Couleur qui change avec le mode clair / sombre (résolue au moment du dessin).
    private static func adaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    static let textColor = adaptive(light: NSColor(calibratedWhite: 0.13, alpha: 1),
                                    dark: NSColor(calibratedWhite: 0.88, alpha: 1))

    /// Interligne aéré.
    static var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = fontSize * 0.35
        return style
    }

    static var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: textColor, .paragraphStyle: paragraphStyle]
    }

    private static let codeBackground = adaptive(light: NSColor(calibratedWhite: 0.965, alpha: 1),
                                                 dark: NSColor(calibratedWhite: 0.17, alpha: 1))
    private static let codeColor = adaptive(light: NSColor(calibratedRed: 0.36, green: 0.30, blue: 0.62, alpha: 1),
                                            dark: NSColor(calibratedRed: 0.74, green: 0.66, blue: 0.96, alpha: 1))
    private static let mutedColor = adaptive(light: NSColor(calibratedWhite: 0.55, alpha: 1),
                                             dark: NSColor(calibratedWhite: 0.60, alpha: 1))
    private static let faintColor = adaptive(light: NSColor(calibratedWhite: 0.68, alpha: 1),
                                             dark: NSColor(calibratedWhite: 0.42, alpha: 1))
    /// Bleu des titres : repère visuel de la structure de la page.
    /// Vert mousse de Cairn pour les #tags.
    private static let tagColor = adaptive(light: NSColor(calibratedRed: 0.24, green: 0.56, blue: 0.49, alpha: 1),
                                           dark: NSColor(calibratedRed: 0.37, green: 0.70, blue: 0.62, alpha: 1))
    private static let headingColor = adaptive(light: NSColor(calibratedRed: 0.08, green: 0.36, blue: 0.75, alpha: 1),
                                               dark: NSColor(calibratedRed: 0.45, green: 0.67, blue: 1.0, alpha: 1))

    private enum Style {
        case heading1, heading2, heading3, bold, list, quote, link, wikiLink, tag, inlineCode, codeBlock, frontMatter, frontMatterTags, variable
    }

    /// Règles appliquées dans l'ordre : la dernière gagne en cas de chevauchement.
    private static let rules: [(NSRegularExpression, Style)] = {
        func regex(_ pattern: String) -> NSRegularExpression {
            // swiftlint:disable:next force_try
            try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        }
        return [
            (regex("^#{3,6}\\s.*$"), .heading3),                                  // ### Titre
            (regex("^##\\s.*$"), .heading2),                                      // ## Titre
            (regex("^#\\s.*$"), .heading1),                                       // # Titre
            (regex("\\*\\*[^*\\n]+\\*\\*"), .bold),                               // **gras**
            (regex("^\\s*(?:[-*+]|\\d+\\.)\\s(?:\\[[ xX]\\]\\s)?"), .list),        // - liste, 1., - [ ]
            (regex("^>.*$"), .quote),                                             // > citation
            (regex("\\[[^\\]\\n]+\\]\\([^)\\n]+\\)"), .link),                      // [texte](lien)
            (regex("!?\\[\\[[^\\]\\n]+\\]\\]"), .wikiLink),                        // [[lien interne]]
            (regex("(?<![\\p{L}\\p{N}_#/&=?.:(\\-])#\\p{L}[\\p{L}\\p{N}_\\-]*"), .tag),     // #tag
            (regex("`[^`\\n]+`"), .inlineCode),                                   // `code`
            (regex("^```.*\\n[\\s\\S]*?^```[ \\t]*$"), .codeBlock),               // ``` bloc ```
            (regex("\\A---\\n[\\s\\S]*?\\n---[ \\t]*$"), .frontMatter),           // en-tête YAML
            (regex("^tags:[ \\t]*(\\S.*)$"), .frontMatterTags),                  // tags: iam, iso27001 (dans l'en-tête)
            (regex("\\{\\{\\s*[A-Za-z0-9_]+\\s*\\}\\}"), .variable),               // {{VARIABLE}}
        ]
    }()

    /// Attributs déjà construits (polices comprises), recalculés seulement si la taille change.
    private static var attributeCache: [Style: [NSAttributedString.Key: Any]] = [:]
    private static var attributeCacheSize: CGFloat = 0

    private static func attributes(for style: Style) -> [NSAttributedString.Key: Any] {
        if attributeCacheSize != fontSize {
            attributeCache = [:]
            attributeCacheSize = fontSize
        }
        if let cached = attributeCache[style] { return cached }
        let built = makeAttributes(for: style)
        attributeCache[style] = built
        return built
    }

    private static func makeAttributes(for style: Style) -> [NSAttributedString.Key: Any] {
        let size = fontSize
        switch style {
        case .heading1:
            return [.font: NSFont.monospacedSystemFont(ofSize: size + 5, weight: .bold), .foregroundColor: headingColor]
        case .heading2:
            return [.font: NSFont.monospacedSystemFont(ofSize: size + 3, weight: .bold), .foregroundColor: headingColor]
        case .heading3:
            return [.font: NSFont.monospacedSystemFont(ofSize: size + 1, weight: .semibold), .foregroundColor: headingColor]
        case .bold:
            return [.font: boldFont]
        case .list:
            return [.foregroundColor: mutedColor]
        case .quote:
            return [.foregroundColor: mutedColor]
        case .link, .wikiLink:
            return [.foregroundColor: NSColor.linkColor]
        case .tag, .frontMatterTags:
            return [.foregroundColor: tagColor]
        case .inlineCode:
            return [.foregroundColor: codeColor, .backgroundColor: codeBackground]
        case .codeBlock:
            return [.foregroundColor: codeColor, .backgroundColor: codeBackground]
        case .frontMatter:
            // En-tête discret : plus petit et très clair.
            return [.font: NSFont.monospacedSystemFont(ofSize: max(size - 2, 9), weight: .regular), .foregroundColor: faintColor]
        case .variable:
            return [.foregroundColor: NSColor.systemTeal, .font: boldFont]
        }
    }

    /// Colore tout le texte (ouverture d'une page, changement de taille de police).
    static func apply(to storage: NSTextStorage) {
        apply(to: storage, in: NSRange(location: 0, length: storage.length), batched: true)
    }

    /// Après une frappe : ne recolore que le paragraphe modifié, sauf si la structure
    /// sur plusieurs lignes (blocs ```, en-tête YAML) a pu changer — alors tout le texte.
    /// Recolorer tout le document à chaque touche forçait macOS à recalculer toute la mise en page.
    static func apply(to storage: NSTextStorage, edited editedRange: NSRange, signature: inout String?) {
        let text = storage.string as NSString
        let current = structureSignature(of: text)
        defer { signature = current }
        let everything = NSRange(location: 0, length: text.length)
        // Appelé pendant le traitement d'une modification : pas de begin/endEditing imbriqués.
        guard let previous = signature, previous == current else { return apply(to: storage, in: everything, batched: false) }

        let location = min(editedRange.location, text.length)
        let paragraph = text.paragraphRange(for: NSRange(location: location, length: min(editedRange.length, text.length - location)))
        if paragraph.location <= frontMatterEnd(of: text) || isInsideFence(text, before: paragraph.location) {
            return apply(to: storage, in: everything, batched: false)
        }
        apply(to: storage, in: paragraph, batched: false)
    }

    private static func apply(to storage: NSTextStorage, in range: NSRange, batched: Bool) {
        let text = storage.string
        if batched { storage.beginEditing() }
        storage.setAttributes(baseAttributes, range: range)
        let headerEnd = frontMatterEnd(of: text as NSString)
        for (regex, style) in rules {
            let attributes = attributes(for: style)
            regex.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let match else { return }
                if style == .frontMatterTags {
                    // Seulement la ligne « tags: » de l'en-tête, et seulement les valeurs (vert sur le gris de l'en-tête).
                    guard match.range.location < headerEnd else { return }
                    storage.addAttributes(attributes, range: match.range(at: 1))
                } else {
                    storage.addAttributes(attributes, range: match.range)
                }
            }
        }
        if batched { storage.endEditing() }
    }

    /// Nombre de « ``` » et fin de l'en-tête : s'ils changent, la coloration de tout le texte peut changer.
    private static func structureSignature(of text: NSString) -> String {
        "\(occurrences(of: "```", in: text, before: text.length))/\(frontMatterEnd(of: text))"
    }

    private static func frontMatterEnd(of text: NSString) -> Int {
        guard text.hasPrefix("---\n"), text.length > 4 else { return -1 }
        let end = text.range(of: "\n---", options: [], range: NSRange(location: 3, length: text.length - 3))
        return end.location == NSNotFound ? text.length : end.location + end.length
    }

    private static func isInsideFence(_ text: NSString, before location: Int) -> Bool {
        occurrences(of: "```", in: text, before: location) % 2 == 1
    }

    private static func occurrences(of needle: String, in text: NSString, before limit: Int) -> Int {
        var count = 0
        var searchRange = NSRange(location: 0, length: min(limit, text.length))
        while searchRange.length > 0 {
            let found = text.range(of: needle, options: .literal, range: searchRange)
            guard found.location != NSNotFound else { break }
            count += 1
            let next = found.location + found.length
            searchRange = NSRange(location: next, length: searchRange.location + searchRange.length - next)
        }
        return count
    }
}
