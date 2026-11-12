import Foundation

/// Résultat de la mise en forme d'un tableau.
struct TableLayout {
    /// Texte du tableau, colonnes alignées (sans retour à la ligne final).
    let text: String
    /// Position (UTF-16, depuis le début du tableau) du texte de chaque cellule : [ligne][colonne].
    let cellRanges: [[NSRange]]
}

/// Aligne les colonnes d'un tableau Markdown :
///
///     | Port | Service |          | Port | Service |
///     |---|---|            ->    | ---- | ------- |
///     | 22 | SSH |                | 22   | SSH     |
enum TableFormatter {

    /// Cellules d'une ligne « | a | b | ».
    static func cells(of line: String) -> [String] {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("|") { text.removeFirst() }
        if text.hasSuffix("|") { text.removeLast() }
        return text.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Ligne de séparation sous l'en-tête : | --- | :---: |
    static func isSeparator(_ cells: [String]) -> Bool {
        !cells.isEmpty && cells.allSatisfy { cell in
            !cell.isEmpty && cell.contains("-") && cell.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    static func layout(rows: [[String]]) -> TableLayout {
        let columns = rows.map(\.count).max() ?? 0
        let padded = rows.map { $0 + Array(repeating: "", count: columns - $0.count) }
        let separators = Set(padded.indices.filter { isSeparator(padded[$0]) })

        // Largeur de chaque colonne (3 minimum, pour « --- »).
        var widths = Array(repeating: 3, count: columns)
        for (rowIndex, row) in padded.enumerated() where !separators.contains(rowIndex) {
            for (column, cell) in row.enumerated() {
                widths[column] = max(widths[column], cell.count)
            }
        }

        var text = ""
        var ranges: [[NSRange]] = []
        for (rowIndex, row) in padded.enumerated() {
            if rowIndex > 0 { text += "\n" }
            var line = "|"
            var rowRanges: [NSRange] = []
            for (column, cell) in row.enumerated() {
                line += " "
                let start = (text as NSString).length + (line as NSString).length
                if separators.contains(rowIndex) {
                    let content = separatorCell(cell, width: widths[column])
                    rowRanges.append(NSRange(location: start, length: 0))
                    line += content
                } else {
                    rowRanges.append(NSRange(location: start, length: (cell as NSString).length))
                    line += cell + String(repeating: " ", count: max(widths[column] - cell.count, 0))
                }
                line += " |"
            }
            text += line
            ranges.append(rowRanges)
        }
        return TableLayout(text: text, cellRanges: ranges)
    }

    /// « --- » à la bonne largeur, en gardant l'alignement (:--- / ---: / :---:).
    private static func separatorCell(_ cell: String, width: Int) -> String {
        let left = cell.hasPrefix(":")
        let right = cell.count > 1 && cell.hasSuffix(":")
        let dashes = max(width - (left ? 1 : 0) - (right ? 1 : 0), 1)
        return (left ? ":" : "") + String(repeating: "-", count: dashes) + (right ? ":" : "")
    }
}
