import Foundation

/// Renommer, fusionner ou retirer un tag dans toutes les pages du wiki.
extension WikiStore {

    /// Nombre de pages qui portent ce tag (pages verrouillées exclues : leur contenu est chiffré).
    func pageCount(forTag key: String) -> Int {
        searchIndex.filter { $0.tagKeys.contains(key) && !$0.isLocked }.count
    }

    /// `newName` nil : retire le tag partout (le mot reste dans le texte, sans « # »).
    /// Si le nouveau nom existe déjà, les deux tags sont fusionnés.
    func renameTag(_ key: String, to newName: String?) {
        let target = newName.map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t#"))
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        if let target, target.isEmpty { return }
        save()

        var changed = 0
        var failures: [String] = []
        let openPath = openURL?.standardizedFileURL.path
        for entry in searchIndex where entry.tagKeys.contains(key) && !entry.isLocked {
            guard let text = try? String(contentsOf: entry.url, encoding: .utf8) else {
                failures.append(entry.title)
                continue
            }
            let updated = TagRewriter.rewrite(key, to: target, in: text)
            guard updated != text else { continue }
            do {
                try updated.write(to: entry.url, atomically: true, encoding: .utf8)
                changed += 1
                if entry.url.standardizedFileURL.path == openPath {
                    rawText = updated
                    savedText = updated
                }
            } catch {
                failures.append(entry.title)
            }
        }

        if searchTagFilter == key { searchTagFilter = target.map(SearchEngine.normalize) }
        reload()
        if let target {
            showToast("#\(target) : \(changed) page\(changed > 1 ? "s" : "") modifiée\(changed > 1 ? "s" : "")")
        } else {
            showToast("Tag retiré de \(changed) page\(changed > 1 ? "s" : "")")
        }
        if !failures.isEmpty {
            errorMessage = "Ces pages n'ont pas pu être modifiées :\n" + failures.map { "• " + $0 }.joined(separator: "\n")
        }
    }
}
