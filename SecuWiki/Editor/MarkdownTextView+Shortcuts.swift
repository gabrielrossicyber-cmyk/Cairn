import AppKit

/// Tab dans les tableaux et Entrée dans les listes.
extension MarkdownTextView {

    // MARK: Tableaux

    /// Tab : cellule suivante (crée une ligne à la fin du tableau). Maj+Tab : cellule précédente.
    /// À chaque Tab, les colonnes du tableau sont alignées automatiquement.
    /// Retourne `false` hors d'un tableau (Tab insère alors une tabulation normale).
    func moveToCell(forward: Bool) -> Bool {
        let ns = string as NSString
        let selection = selectedRange()
        guard !isInsideCodeFence(selection.location) else { return false }
        let caretLine = lineContentRange(at: selection.location)
        guard isTableRow(caretLine) else { return false }

        // 1. Toutes les lignes du tableau autour du curseur.
        var lines = [caretLine]
        var start = caretLine.location
        while start > 0 {
            let previous = lineContentRange(at: start - 1)
            guard previous.location < start, isTableRow(previous) else { break }
            lines.insert(previous, at: 0)
            start = previous.location
        }
        var end = NSMaxRange(caretLine)
        while end < ns.length {
            let next = lineContentRange(at: end + 1)
            guard next.location > end, isTableRow(next) else { break }
            lines.append(next)
            end = NSMaxRange(next)
        }
        let tableRange = NSRange(location: lines[0].location, length: end - lines[0].location)
        let caretRow = lines.firstIndex(of: caretLine) ?? 0

        // 2. Cellules, et colonne du curseur (nombre de « | » avant lui).
        var rows = lines.map { TableFormatter.cells(of: ns.substring(with: $0)) }
        let columns = max(rows.map(\.count).max() ?? 1, 1)
        let separators = Set(rows.indices.filter { TableFormatter.isSeparator(rows[$0]) })
        let lineText = ns.substring(with: caretLine) as NSString
        let offset = min((forward ? NSMaxRange(selection) : selection.location) - caretLine.location, lineText.length)
        let pipesBefore = (0..<max(offset, 0)).filter { lineText.character(at: $0) == 0x7C }.count
        let caretColumn = min(max(pipesBefore - 1, 0), columns - 1)

        // 3. Cellule visée.
        var targetRow = caretRow
        var targetColumn = caretColumn
        if forward {
            if caretColumn + 1 < columns && !separators.contains(caretRow) {
                targetColumn = caretColumn + 1
            } else {
                targetColumn = 0
                targetRow = caretRow + 1
                while separators.contains(targetRow) { targetRow += 1 }
                if targetRow >= rows.count {
                    rows.append(Array(repeating: "", count: columns)) // nouvelle ligne
                    targetRow = rows.count - 1
                }
            }
        } else {
            if caretColumn > 0 && !separators.contains(caretRow) {
                targetColumn = caretColumn - 1
            } else {
                var row = caretRow - 1
                while row >= 0 && separators.contains(row) { row -= 1 }
                if row >= 0 {
                    targetRow = row
                    targetColumn = columns - 1
                } else {
                    targetColumn = 0
                }
            }
        }

        // 4. Tableau aligné + sélection du texte de la cellule (curseur si elle est vide).
        let layout = TableFormatter.layout(rows: rows)
        let cell = layout.cellRanges[targetRow][targetColumn]
        let target = NSRange(location: tableRange.location + cell.location, length: cell.length)
        if layout.text != ns.substring(with: tableRange) {
            replace(tableRange, with: layout.text, selecting: target)
        } else {
            setSelectedRange(target)
            scrollRangeToVisible(target)
        }
        return true
    }

    private func isTableRow(_ line: NSRange) -> Bool {
        (string as NSString).substring(with: line).trimmingCharacters(in: .whitespaces).hasPrefix("|")
    }

    // MARK: Listes

    private static let listPattern = try! NSRegularExpression( // swiftlint:disable:this force_try
        pattern: "^(\\s*)(?:([-*+])|(\\d+)\\.)\\s(\\[[ xX]\\]\\s)?"
    )

    private static let quotePattern = try! NSRegularExpression( // swiftlint:disable:this force_try
        pattern: "^(\\s*)>[ ]?"
    )

    /// Entrée sur un élément de liste : nouvel élément du même type.
    /// Entrée dans un encadré (> …) : nouvelle ligne de l'encadré.
    /// Entrée sur un élément vide : fin de la liste ou de l'encadré.
    func continueList() -> Bool {
        let selection = selectedRange()
        guard selection.length == 0, !isInsideCodeFence(selection.location) else { return false }
        let line = lineContentRange(at: selection.location)
        let lineText = (string as NSString).substring(with: line) as NSString

        // Encadré / citation
        if let quote = Self.quotePattern.firstMatch(
            in: lineText as String, range: NSRange(location: 0, length: lineText.length)
        ) {
            if quote.range.length == lineText.length {
                replace(line, with: "", selecting: NSRange(location: line.location, length: 0))
                return true
            }
            guard selection.location >= line.location + quote.range.length else { return false }
            let indent = lineText.substring(with: quote.range(at: 1))
            replace(selection, with: "\n\(indent)> ", selecting: nil)
            return true
        }

        guard let match = Self.listPattern.firstMatch(
            in: lineText as String, range: NSRange(location: 0, length: lineText.length)
        ) else { return false }

        // Élément vide (« - » seul) : on retire le marqueur et on sort de la liste.
        if match.range.length == lineText.length {
            replace(line, with: "", selecting: NSRange(location: line.location, length: 0))
            return true
        }
        // Curseur dans le marqueur lui-même : comportement normal.
        guard selection.location >= line.location + match.range.length else { return false }

        let indent = lineText.substring(with: match.range(at: 1))
        var marker = "-"
        if match.range(at: 2).location != NSNotFound {
            marker = lineText.substring(with: match.range(at: 2))
        } else if match.range(at: 3).location != NSNotFound {
            let number = Int(lineText.substring(with: match.range(at: 3))) ?? 0
            marker = "\(number + 1)."
        }
        let checkbox = match.range(at: 4).location != NSNotFound ? "[ ] " : ""
        replace(selection, with: "\n\(indent)\(marker) \(checkbox)", selecting: nil)
        return true
    }
}
