import Foundation

/// Mode examen : périmètre des questions et historique des notes.
extension WikiStore {

    func startExam() {
        guard rootURL != nil else { return }
        save()
        isSearchPresented = false
        isExamPresented = true
    }

    /// Pages du périmètre choisi (dossier relatif, vide = tout le wiki ; tag = clé normalisée).
    func examEntries(folder: String, tag: String?) -> [SearchEntry] {
        let entries = entries(inFolder: folder)
        guard let tag else { return entries }
        return entries.filter { $0.tagKeys.contains(tag) }
    }

    func examScopeLabel(folder: String, tag: String?) -> String {
        var parts: [String] = []
        if !folder.isEmpty {
            parts.append(folder.split(separator: "/").last.map { WikiScanner.displayName(String($0)) } ?? folder)
        }
        if let tag { parts.append("#" + tagName(tag)) }
        return parts.isEmpty ? "Tout le wiki" : parts.joined(separator: " · ")
    }

    /// Enregistre la note dans le wiki (50 derniers examens).
    func recordExam(_ result: ExamResult) {
        wikiSettings.examHistory = Array(([result] + wikiSettings.examHistory).prefix(50))
        saveWikiSettings()
    }
}
