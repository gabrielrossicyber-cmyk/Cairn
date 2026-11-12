import SwiftUI
import AppKit

/// Éditeur Markdown brut, basé sur MarkdownTextView (NSTextView enrichi).
/// Recherche avec Cmd+F, annulation avec Cmd+Z, commandes « / », Tab dans les tableaux.
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    /// Change quand on ouvre une autre page : remet le curseur en haut et vide l'historique d'annulation.
    let documentID: URL?
    /// Pages proposées après « [[ ».
    var pageProvider: () -> [WikiLinkTarget] = { [] }
    /// Clic dans le sommaire : le curseur va sur le titre.
    var tocRequest: TOCRequest?
    /// Taille de la police (Réglages > Éditeur).
    var fontSize: Double = Prefs.Defaults.editorFontSize
    /// Commandes « / » supplémentaires (modèles personnels).
    var extraCommands: () -> [SlashCommand] = { [] }
    /// Défilement synchronisé avec l'aperçu (mode côte à côte).
    var scrollSync: ScrollSync?

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = .textBackgroundColor

        // Montage classique d'une NSTextView dans une NSScrollView (retour à la ligne automatique).
        let contentSize = scrollView.contentSize
        let textView = MarkdownTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView

        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator
        MarkdownHighlighter.fontSize = CGFloat(fontSize)
        context.coordinator.fontSize = fontSize
        configure(textView)
        textView.string = text
        textView.documentURL = documentID
        textView.pageProvider = pageProvider
        textView.extraCommands = extraCommands
        context.coordinator.documentID = documentID

        // Défilement de l'éditeur -> l'aperçu suit.
        context.coordinator.textView = textView
        context.coordinator.scrollSync = scrollSync
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.editorDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scrollView.documentView as? MarkdownTextView else { return }
        textView.documentURL = documentID
        textView.pageProvider = pageProvider
        textView.extraCommands = extraCommands
        context.coordinator.scrollSync = scrollSync

        // Taille de police modifiée dans les Réglages : on recolore tout le texte.
        if context.coordinator.fontSize != fontSize {
            context.coordinator.fontSize = fontSize
            MarkdownHighlighter.fontSize = CGFloat(fontSize)
            textView.font = MarkdownHighlighter.baseFont
            textView.defaultParagraphStyle = MarkdownHighlighter.paragraphStyle
            textView.typingAttributes = MarkdownHighlighter.baseAttributes
            if let storage = textView.textStorage { MarkdownHighlighter.apply(to: storage) }
            context.coordinator.structureSignature = nil
        }

        let documentChanged = context.coordinator.documentID != documentID
        if documentChanged || textView.string != text {
            textView.string = text
            if documentChanged {
                context.coordinator.documentID = documentID
                textView.undoManager?.removeAllActions()
                textView.setSelectedRange(NSRange(location: 0, length: 0))
                textView.scrollToBeginningOfDocument(nil)
            }
        }

        // Sommaire : place le curseur sur le titre demandé.
        if let request = tocRequest, request.id != context.coordinator.lastTOCID {
            context.coordinator.lastTOCID = request.id
            let location = min(request.location, (textView.string as NSString).length)
            textView.setSelectedRange(NSRange(location: location, length: 0))
            textView.scrollRangeToVisible(NSRange(location: location, length: 0))
            textView.window?.makeFirstResponder(textView)
        }
    }

    private func configure(_ textView: NSTextView) {
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        // Pas de « correction » automatique : elle casserait les commandes et le code.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false

        textView.font = MarkdownHighlighter.baseFont
        textView.textColor = MarkdownHighlighter.textColor
        textView.typingAttributes = MarkdownHighlighter.baseAttributes
        textView.backgroundColor = .textBackgroundColor // s'adapte au mode clair / sombre
        textView.insertionPointColor = .controlAccentColor
        textView.defaultParagraphStyle = MarkdownHighlighter.paragraphStyle
        (textView as? MarkdownTextView)?.updateColumnInsets()
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var text: Binding<String>
        var documentID: URL?
        var lastTOCID: UUID?
        var fontSize: Double = 0
        weak var textView: NSTextView?
        var scrollSync: ScrollSync?

        /// Début (en UTF-16) de chaque ligne du texte. Recalculé seulement après une modification,
        /// pas à chaque événement de défilement (120 par seconde sur un trackpad).
        private var lineStarts: [Int]?
        /// Structure du texte (blocs ```, en-tête) au dernier coloriage : voir MarkdownHighlighter.
        var structureSignature: String?

        /// Ligne affichée en haut de l'éditeur, avec sa fraction (12,4 = 40 % de la ligne 12),
        /// transmise à l'aperçu. La fraction rend le suivi continu dans les longs paragraphes
        /// (une seule ligne du texte, mais plusieurs lignes à l'écran) au lieu de sauts.
        @objc func editorDidScroll(_ notification: Notification) {
            guard let scrollSync, scrollSync.isEnabled, let textView,
                  let layoutManager = textView.layoutManager,
                  let container = textView.textContainer else { return }
            let length = (textView.string as NSString).length
            guard length > 0 else { return scrollSync.editorScrolled(toLine: 0) }

            let top = max(textView.visibleRect.minY - textView.textContainerInset.height, 0)
            let glyph = layoutManager.glyphIndex(for: NSPoint(x: 0, y: top), in: container)
            let character = layoutManager.characterIndexForGlyph(at: glyph)

            let starts = currentLineStarts(of: textView)
            let line = Self.lastIndex(in: starts, notAfter: character)

            // Hauteur de la ligne trouvée -> position relative du haut de l'écran dans cette ligne.
            let lineTop = layoutManager.lineFragmentRect(
                forGlyphAt: layoutManager.glyphIndexForCharacter(at: starts[line]), effectiveRange: nil
            ).minY
            var nextTop = layoutManager.usedRect(for: container).maxY
            if line + 1 < starts.count, starts[line + 1] < length {
                nextTop = layoutManager.lineFragmentRect(
                    forGlyphAt: layoutManager.glyphIndexForCharacter(at: starts[line + 1]), effectiveRange: nil
                ).minY
            }
            let fraction = nextTop > lineTop ? min(max((top - lineTop) / (nextTop - lineTop), 0), 1) : 0
            scrollSync.editorScrolled(toLine: Double(line) + Double(fraction))
        }

        private func currentLineStarts(of textView: NSTextView) -> [Int] {
            if let lineStarts { return lineStarts }
            var starts = [0]
            var offset = 0
            for unit in textView.string.utf16 {
                offset += 1
                if unit == 10 { starts.append(offset) }
            }
            lineStarts = starts
            return starts
        }

        /// Recherche dichotomique : dernière ligne qui commence avant (ou à) `value`.
        private static func lastIndex(in starts: [Int], notAfter value: Int) -> Int {
            var low = 0, high = starts.count - 1
            while low < high {
                let middle = (low + high + 1) / 2
                if starts[middle] <= value { low = middle } else { high = middle - 1 }
            }
            return low
        }

        init(text: Binding<String>) {
            self.text = text
        }

        /// Chaque frappe remonte le texte vers le store (qui enregistre 1 s plus tard).
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }

        /// Le curseur a bougé : le menu « / » se met à jour (ou se ferme).
        func textViewDidChangeSelection(_ notification: Notification) {
            (notification.object as? MarkdownTextView)?.setNeedsSlashMenuUpdate()
        }

        /// Touches spéciales : Entrée, Tab, flèches, Échap.
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            (textView as? MarkdownTextView)?.handleCommand(commandSelector) ?? false
        }

        /// Recolore le Markdown après chaque modification du texte.
        func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters) else { return }
            lineStarts = nil
            MarkdownHighlighter.apply(to: textStorage, edited: editedRange, signature: &structureSignature)
        }
    }
}
