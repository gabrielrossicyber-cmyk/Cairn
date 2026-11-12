import Foundation

/// Tableau de bord personnalisable : liste des widgets et données qu'ils affichent.
extension WikiStore {

    var dashboardWidgets: [DashboardWidget] {
        wikiSettings.dashboard ?? DashboardWidget.defaultLayout
    }

    /// Enregistre la nouvelle disposition dans .secuwiki.json.
    func setDashboard(_ widgets: [DashboardWidget]) {
        wikiSettings.dashboard = widgets
        saveWikiSettings()
    }

    func updateWidget(_ widget: DashboardWidget) {
        var widgets = dashboardWidgets
        guard let index = widgets.firstIndex(where: { $0.id == widget.id }) else { return }
        widgets[index] = widget
        setDashboard(widgets)
    }

    func addWidget(_ kind: DashboardWidget.Kind) {
        setDashboard(dashboardWidgets + [DashboardWidget(kind: kind)])
    }

    func removeWidget(_ id: UUID) {
        setDashboard(dashboardWidgets.filter { $0.id != id })
    }

    func moveWidget(_ id: UUID, by offset: Int) {
        var widgets = dashboardWidgets
        guard let index = widgets.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard widgets.indices.contains(target) else { return }
        widgets.swapAt(index, target)
        setDashboard(widgets)
    }

    func resetDashboard() {
        wikiSettings.dashboard = nil
        saveWikiSettings()
    }

    /// Dossiers du wiki (chemins relatifs), pour les widgets « Contenu d'un dossier » et « À faire ».
    var dashboardFolderOptions: [DashboardFolderOption] {
        guard let rootURL else { return [] }
        let rootCount = rootURL.standardizedFileURL.pathComponents.count
        var options: [DashboardFolderOption] = []
        func walk(_ list: [WikiNode], depth: Int) {
            for node in list where node.isFolder {
                if SearchEngine.isTemplatesFolder(node.url.lastPathComponent) { continue }
                let path = node.url.standardizedFileURL.pathComponents.dropFirst(rootCount).joined(separator: "/")
                options.append(DashboardFolderOption(path: path, label: String(repeating: "   ", count: depth) + node.name))
                walk(node.children ?? [], depth: depth + 1)
            }
        }
        walk(nodes, depth: 0)
        return options
    }

    /// Pages dont le fichier est dans ce dossier (ou ses sous-dossiers). Dossier vide = tout le wiki.
    func entries(inFolder folder: String) -> [SearchEntry] {
        guard !folder.isEmpty, let rootURL else { return searchIndex }
        let prefix = rootURL.appendingPathComponent(folder).standardizedFileURL.path + "/"
        return searchIndex.filter { $0.url.standardizedFileURL.path.hasPrefix(prefix) }
    }
}

struct DashboardFolderOption: Hashable {
    let path: String
    let label: String
}

// MARK: Questions de révision

/// Une question tirée des blocs « > [!REPONSE] » du wiki.
struct RevisionQuestion: Identifiable, Equatable {
    let id = UUID()
    let question: String
    let answer: String
    let page: SearchEntry

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }

    /// La question = la ligne juste avant l'encadré (« **Question :** … »), la réponse = l'encadré.
    static func all(in entries: [SearchEntry]) -> [RevisionQuestion] {
        var result: [RevisionQuestion] = []
        for entry in entries {
            let lines = entry.lines
            for index in lines.indices where !entry.isCode[index] {
                let lower = lines[index].lowercased()
                guard lower.contains("[!reponse]") || lower.contains("[!réponse]") || lower.contains("[!answer]"),
                      index > 0 else { continue }

                var answer: [String] = []
                var next = index + 1
                while next < lines.count, lines[next].hasPrefix(">") {
                    let text = lines[next].drop { $0 == ">" || $0 == " " }
                    if !text.isEmpty { answer.append(String(text)) }
                    next += 1
                }
                let question = cleanQuestion(lines[index - 1])
                guard !question.isEmpty, !answer.isEmpty else { continue }
                result.append(RevisionQuestion(question: question, answer: answer.joined(separator: "\n"), page: entry))
            }
        }
        return result
    }

    private static func cleanQuestion(_ line: String) -> String {
        var text = line
        for prefix in ["**Question :**", "**Question:**", "Question :", "Question:"] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        if text.hasPrefix("#") { text = String(text.drop { $0 == "#" }) }
        return text.trimmingCharacters(in: .whitespaces)
    }
}
