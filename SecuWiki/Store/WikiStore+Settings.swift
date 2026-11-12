import Foundation

/// Réglages du wiki (.secuwiki.json) et ce qui en dépend.
extension WikiStore {

    private var settingsURL: URL? {
        rootURL?.appendingPathComponent(".secuwiki.json")
    }

    func loadWikiSettings() {
        guard let url = settingsURL,
              let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(WikiSettings.self, from: data) else {
            if !wikiSettings.hasSameContent(as: WikiSettings()) && !FileManager.default.fileExists(atPath: settingsURL?.path ?? "") {
                wikiSettings = WikiSettings()
            }
            return
        }
        // Rien de nouveau (souvent : c'est nous qui venons d'écrire le fichier) -> on ne touche à rien.
        guard !settings.hasSameContent(as: wikiSettings) else { return }
        wikiSettings = settings
        syncCurrentWikiName()
    }

    func saveWikiSettings() {
        guard let url = settingsURL else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(wikiSettings).write(to: url, options: .atomic)
            syncCurrentWikiName()
        } catch {
            errorMessage = "Impossible d'enregistrer les réglages du wiki : \(error.localizedDescription)"
        }
    }

    /// Nom affiché : celui des réglages, sinon le nom du dossier.
    var wikiDisplayName: String {
        let name = wikiSettings.name.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { return name }
        return rootURL?.lastPathComponent ?? "Cairn"
    }

    /// Variables de la page + variables globales du wiki (la page est prioritaire).
    func effectiveVariables(_ page: MarkdownPage) -> [PageVariable] {
        let pageNames = Set(page.variables.map(\.name))
        let globals = wikiSettings.globalVariables
            .map { PageVariable(name: $0.name.trimmingCharacters(in: .whitespaces), value: $0.value) }
            .filter { !$0.name.isEmpty && !pageNames.contains($0.name) }
        return page.variables + globals
    }

    /// Valeur globale d'une variable (affichée en grisé dans la barre Variables).
    func globalValue(of name: String) -> String? {
        wikiSettings.globalVariables.first { $0.name.trimmingCharacters(in: .whitespaces) == name }?.value
    }

    // MARK: Modèles de page

    /// Modèles intégrés proposés à la création d'une page.
    static let templateTriggers = ["cours", "revision", "lab", "incident", "procedure", "outil", "cve", "mitre", "glossaire"]

    /// Tous les modèles : intégrés + personnels (dossier _Modèles).
    var templateOptions: [SlashCommand] {
        Self.templateTriggers.compactMap { trigger in SlashCommand.all.first { $0.trigger == trigger } } + customTemplates
    }

    /// Modèles affichés dans la fenêtre « Nouvelle page » (sans ceux masqués dans les Réglages).
    var creationTemplates: [SlashCommand] {
        templateOptions.filter { !wikiSettings.hiddenTemplates.contains($0.trigger) }
    }

    /// Texte d'un modèle (vide = page vide).
    func templateBody(_ trigger: String) -> String {
        guard !trigger.isEmpty,
              let command = (SlashCommand.all + customTemplates).first(where: { $0.trigger == trigger }) else { return "" }
        return Snippet(template: command.template()).text
    }

    /// Modèle par défaut (utilisé pour la page d'un dossier et les liens [[…]] vers une page à créer).
    var defaultTemplateBody: String {
        templateBody(wikiSettings.defaultTemplate)
    }

    /// Dossier des modèles personnels, s'il existe.
    var templatesFolderURL: URL? {
        guard let rootURL,
              let items = try? FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil) else { return nil }
        return items.first { SearchEngine.isTemplatesFolder($0.lastPathComponent) }
    }

    /// Chaque fichier .md de _Modèles devient une commande « / » et un modèle de page.
    func loadCustomTemplates() {
        guard let folder = templatesFolderURL,
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            customTemplates = []
            return
        }
        let builtIn = Set(SlashCommand.all.map(\.trigger))
        var commands: [SlashCommand] = []
        for file in files.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending })
        where file.pathExtension.lowercased() == "md" {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let page = MarkdownPage.parse(text)
            let name = file.deletingPathExtension().lastPathComponent
            let title = page.frontMatter["title"].flatMap { $0.isEmpty ? nil : $0 } ?? WikiScanner.displayName(name)

            // Déclencheur : nom du fichier sans accents ni symboles (« Rapport-pentest » -> /rapportpentest).
            var trigger = SearchEngine.normalize(name).filter { $0.isLetter || $0.isNumber }
            if trigger.isEmpty { continue }
            while builtIn.contains(trigger) || commands.contains(where: { $0.trigger == trigger }) { trigger += "2" }

            // Le titre « # … » du modèle est retiré : la nouvelle page a déjà le sien.
            var lines = page.body.components(separatedBy: "\n")
            if let first = lines.first, first.hasPrefix("# ") { lines.removeFirst() }
            let body = lines.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"

            commands.append(SlashCommand(trigger: trigger, title: title, detail: "Modèle personnel · \(file.lastPathComponent)",
                                         icon: "doc.badge.plus") { body })
        }
        customTemplates = commands
    }

    /// Crée le dossier _Modèles avec un exemple, puis l'affiche.
    func createTemplatesFolder() {
        guard let rootURL else { return }
        let folder = templatesFolderURL ?? rootURL.appendingPathComponent("_Modèles", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let example = folder.appendingPathComponent("Compte-rendu-de-TP.md")
            if !FileManager.default.fileExists(atPath: example.path) {
                try """
                ---
                title: Compte rendu de TP
                ---

                # Compte rendu de TP

                ## Contexte
                ⟦Module, date, objectif du TP.⟧

                ## Ce que j'ai fait
                1. 

                ## Ce que j'ai appris
                - 

                ## Points à revoir
                - [ ] 

                """.write(to: example, atomically: true, encoding: .utf8)
            }
            reload()
            showToast("Dossier _Modèles prêt : chaque fichier .md devient un modèle")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
