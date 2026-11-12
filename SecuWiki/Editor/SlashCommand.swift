import Foundation

/// Une commande du menu « / » de l'éditeur.
///
/// Dans un modèle :
/// - `⟦texte⟧` = texte sélectionné après l'insertion (tu tapes directement par-dessus) ;
/// - `‸` = position du curseur.
struct SlashCommand: Identifiable {
    let trigger: String
    let title: String
    let detail: String
    let icon: String
    /// Autres mots qui trouvent la commande (/tableau trouve /table).
    var aliases: [String] = []
    /// Un bloc commence toujours sur sa propre ligne.
    var isBlock = true
    let template: () -> String

    var id: String { trigger }

    // MARK: Liste des commandes

    static let all: [SlashCommand] = [
        SlashCommand(trigger: "table", title: "Tableau", detail: "3 colonnes, 2 lignes — Tab pour passer à la cellule suivante",
                     icon: "tablecells", aliases: ["tableau"]) {
            "| ⟦Colonne 1⟧ | Colonne 2 | Colonne 3 |\n| --- | --- | --- |\n|  |  |  |\n|  |  |  |\n"
        },
        SlashCommand(trigger: "cours", title: "Note de cours", detail: "Notions clés, explications, à retenir, questions d'examen",
                     icon: "book", aliases: ["notecours", "lecon", "module"]) { SlashTemplates.course() },
        SlashCommand(trigger: "revision", title: "Fiche de révision", detail: "Définition, exemple concret, question de compréhension",
                     icon: "graduationcap", aliases: ["fiche", "examen", "brevet"]) { SlashTemplates.revision },
        SlashCommand(trigger: "question", title: "Question + réponse masquée", detail: "Pour réviser : la réponse s'affiche au clic",
                     icon: "questionmark.bubble", aliases: ["quiz", "flashcard", "carte"]) {
            "**Question :** ⟦Ta question⟧\n\n> [!REPONSE]\n> \n"
        },
        SlashCommand(trigger: "reponse", title: "Réponse masquée", detail: "Encadré gris replié, cliquer pour afficher",
                     icon: "eye.slash", aliases: ["solution", "cacher"]) {
            "> [!REPONSE]\n> ⟦réponse⟧\n"
        },
        SlashCommand(trigger: "lab", title: "Modèle de lab", detail: "Objectif, environnement, étapes, commandes, résultat…",
                     icon: "flask", aliases: ["modele", "template"]) { SlashCommand.labTemplate },
        SlashCommand(trigger: "incident", title: "Rapport d'incident", detail: "Résumé, chronologie, analyse, confinement… (NIST 800-61)",
                     icon: "flame", aliases: ["inc", "rapport", "soc"]) { SlashTemplates.incident() },
        SlashCommand(trigger: "glossaire", title: "Glossaire (tableau)", detail: "Terme, définition, exemple — Tab en fin de tableau ajoute un terme",
                     icon: "character.book.closed", aliases: ["terme", "definition", "vocabulaire"]) { SlashTemplates.glossary },
        SlashCommand(trigger: "cve", title: "Fiche vulnérabilité", detail: "CVE, CVSS, impact, détection, remédiation",
                     icon: "ladybug", aliases: ["vulnerabilite", "vuln", "faille"]) { SlashTemplates.vulnerability },
        SlashCommand(trigger: "mitre", title: "Technique MITRE ATT&CK", detail: "Tactique, fonctionnement, détection SOC, mitigation",
                     icon: "scope", aliases: ["attaque", "technique", "attck"]) { SlashTemplates.mitre },
        SlashCommand(trigger: "outil", title: "Fiche outil", detail: "Usage, installation, commandes essentielles, pièges",
                     icon: "wrench.and.screwdriver", aliases: ["tool", "logiciel"]) { SlashTemplates.tool },
        SlashCommand(trigger: "procedure", title: "Procédure / runbook", detail: "Objectif, prérequis, étapes, vérification, retour arrière",
                     icon: "list.clipboard", aliases: ["runbook", "sop", "mode"]) { SlashTemplates.procedure },
        SlashCommand(trigger: "variable", title: "Variable {{NOM}}", detail: "Un NOM entre {{ }}, la valeur se règle dans la barre Variables",
                     icon: "curlybraces", aliases: ["var", "ip"], isBlock: false) {
            "{{⟦IP_CIBLE⟧}}"
        },
        SlashCommand(trigger: "lien", title: "Lien vers une page du wiki", detail: "[[Nom de la page]] — ou tape directement [[",
                     icon: "link.badge.plus", aliases: ["page", "wiki", "interne"], isBlock: false) {
            "[[⟦Nom de la page⟧]]"
        },
        SlashCommand(trigger: "flux", title: "Flux simple", detail: "Étape > Étape > Étape : dessiné en schéma",
                     icon: "arrow.right.circle", aliases: ["processus", "chaine", "fleche", "workflow"]) {
            "```flux\n⟦Préparer⟧ > Détecter > Contenir > Éradiquer > Récupérer\n```\n"
        },
        SlashCommand(trigger: "schema", title: "Schéma (flowchart)", detail: "Diagramme Mermaid : réseau, flux, architecture",
                     icon: "point.3.connected.trianglepath.dotted", aliases: ["diagramme", "mermaid", "reseau"]) {
            "```mermaid\nflowchart LR\n    A[⟦Attaquant⟧] --> B[Pare-feu]\n    B --> C[Serveur web]\n    C --> D[(Base de données)]\n```\n"
        },
        SlashCommand(trigger: "classe", title: "UML : diagramme de classes", detail: "Classes, attributs, méthodes, relations",
                     icon: "square.stack.3d.up", aliases: ["uml", "class", "objet"]) { SlashTemplates.umlClass },
        SlashCommand(trigger: "etat", title: "UML : diagramme d'états", detail: "Cycle de vie : incident, ticket, compte…",
                     icon: "circle.dashed", aliases: ["uml", "state", "cycle"]) { SlashTemplates.umlState },
        SlashCommand(trigger: "activite", title: "UML : diagramme d'activité", detail: "Étapes et décisions d'un traitement",
                     icon: "arrow.triangle.branch", aliases: ["uml", "activity", "algo"]) { SlashTemplates.umlActivity },
        SlashCommand(trigger: "er", title: "Modèle entité-relation", detail: "Tables et liens d'une base de données",
                     icon: "cylinder.split.1x2", aliases: ["uml", "base", "bdd", "entite"]) { SlashTemplates.entityRelation },
        SlashCommand(trigger: "bpmn", title: "Processus BPMN", detail: "Couloirs (acteurs), événements, tâches, décisions",
                     icon: "flowchart", aliases: ["processus", "workflow", "metier"]) { SlashTemplates.bpmn },
        SlashCommand(trigger: "sequence", title: "UML : diagramme de séquence", detail: "Échanges entre acteurs (handshake, authentification…)",
                     icon: "arrow.left.arrow.right", aliases: ["uml", "echanges", "messages"]) {
            "```mermaid\nsequenceDiagram\n    participant C as ⟦Client⟧\n    participant S as Serveur\n    C->>S: SYN\n    S->>C: SYN-ACK\n    C->>S: ACK\n```\n"
        },
        SlashCommand(trigger: "bash", title: "Commande bash", detail: "Bloc de code Linux / macOS",
                     icon: "terminal", aliases: ["shell", "linux", "commande"]) {
            "```bash\n‸\n```\n"
        },
        SlashCommand(trigger: "powershell", title: "Commande PowerShell", detail: "Bloc de code Windows",
                     icon: "terminal.fill", aliases: ["ps", "windows"]) {
            "```powershell\n‸\n```\n"
        },
        SlashCommand(trigger: "python", title: "Code Python", detail: "Bloc de code Python",
                     icon: "curlybraces", aliases: ["py", "script"]) {
            "```python\n‸\n```\n"
        },
        SlashCommand(trigger: "yaml", title: "YAML / config", detail: "Bloc de configuration",
                     icon: "doc.plaintext", aliases: ["config", "json"]) {
            "```yaml\n‸\n```\n"
        },
        SlashCommand(trigger: "code", title: "Bloc de code", detail: "Langage à préciser",
                     icon: "chevron.left.forwardslash.chevron.right", aliases: ["bloc"]) {
            "```⟦langage⟧\n\n```\n"
        },
        SlashCommand(trigger: "h1", title: "Titre 1", detail: "# Grand titre", icon: "textformat.size", aliases: ["titre"]) {
            "# ⟦Titre⟧\n"
        },
        SlashCommand(trigger: "h2", title: "Titre 2", detail: "## Section", icon: "textformat.size", aliases: ["titre", "section"]) {
            "## ⟦Section⟧\n"
        },
        SlashCommand(trigger: "h3", title: "Titre 3", detail: "### Sous-section", icon: "textformat.size", aliases: ["titre"]) {
            "### ⟦Sous-section⟧\n"
        },
        SlashCommand(trigger: "todo", title: "Liste de tâches", detail: "- [ ] Entrée ajoute une tâche",
                     icon: "checklist", aliases: ["tache", "checklist"]) {
            "- [ ] ⟦Tâche⟧\n"
        },
        SlashCommand(trigger: "liste", title: "Liste à puces", detail: "- Entrée ajoute un élément",
                     icon: "list.bullet", aliases: ["puces", "bullet"]) {
            "- ⟦Élément⟧\n"
        },
        SlashCommand(trigger: "etapes", title: "Liste numérotée", detail: "1. Entrée ajoute une étape",
                     icon: "list.number", aliases: ["numero", "steps"]) {
            "1. ⟦Étape⟧\n"
        },
        // Encadrés colorés (syntaxe GitHub : > [!NOTE], > [!CAUTION]…). Entrée ajoute une ligne à l'encadré.
        SlashCommand(trigger: "information", title: "Information (bleu)", detail: "Encadré bleu",
                     icon: "info.circle", aliases: ["note", "info"]) {
            "> [!NOTE]\n> ⟦texte⟧\n"
        },
        SlashCommand(trigger: "attention", title: "Attention (rouge)", detail: "Encadré rouge : danger, action risquée",
                     icon: "exclamationmark.octagon", aliases: ["danger", "caution"]) {
            "> [!CAUTION]\n> ⟦texte⟧\n"
        },
        SlashCommand(trigger: "avertissement", title: "Avertissement (orange)", detail: "Encadré orange : point de vigilance",
                     icon: "exclamationmark.triangle", aliases: ["warning", "vigilance"]) {
            "> [!WARNING]\n> ⟦texte⟧\n"
        },
        SlashCommand(trigger: "astuce", title: "Astuce (vert)", detail: "Encadré vert : conseil, bonne pratique",
                     icon: "lightbulb", aliases: ["tip", "conseil"]) {
            "> [!TIP]\n> ⟦texte⟧\n"
        },
        SlashCommand(trigger: "url", title: "Lien web", detail: "[texte](https://…)", icon: "link",
                     aliases: ["link", "web"], isBlock: false) {
            "[⟦texte⟧](https://)"
        },
        SlashCommand(trigger: "image", title: "Image", detail: "![description](assets/…)", icon: "photo",
                     aliases: ["capture", "screenshot"], isBlock: false) {
            "![⟦description⟧](assets/image.png)"
        },
        SlashCommand(trigger: "separateur", title: "Séparateur", detail: "Ligne horizontale", icon: "minus",
                     aliases: ["ligne", "hr"]) {
            "---\n‸"
        },
        SlashCommand(trigger: "date", title: "Date du jour", detail: "AAAA-MM-JJ", icon: "calendar",
                     aliases: ["aujourdhui"], isBlock: false) {
            Date.now.formatted(.iso8601.year().month().day())
        },
    ]

    /// Commandes correspondant à ce qui est tapé après « / » (sans tenir compte des accents ni des majuscules).
    static func matching(_ query: String, in commands: [SlashCommand] = all) -> [SlashCommand] {
        let q = normalize(query)
        guard !q.isEmpty else { return commands }
        let byTrigger = commands.filter { $0.trigger.hasPrefix(q) }
        let byOther = commands.filter { command in
            !command.trigger.hasPrefix(q)
                && (normalize(command.title).contains(q) || command.aliases.contains { $0.hasPrefix(q) })
        }
        return byTrigger + byOther
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    }

    // MARK: Modèle de lab

    private static let labTemplate = """
    ## Objectif
    ⟦Ce que ce lab doit démontrer.⟧

    ## Prérequis
    - 

    ## Environnement
    | Machine | OS | IP | Rôle |
    | --- | --- | --- | --- |
    |  |  |  |  |

    ## Étapes
    1. 

    ## Commandes
    ```bash

    ```

    ## Résultat attendu
    - [ ] 

    ## Dépannage
    | Problème | Cause | Solution |
    | --- | --- | --- |
    |  |  |  |

    ## Références
    - MITRE ATT&CK : 
    - Note de cours Notion : 

    """
}

/// Un modèle prêt à insérer : texte final + zone à sélectionner.
struct Snippet {
    private(set) var text: String
    private(set) var selection: NSRange?

    init(template: String) {
        var ns = template as NSString
        var selection: NSRange?
        let open = ns.range(of: "⟦")
        if open.location != NSNotFound {
            let afterOpen = NSRange(location: NSMaxRange(open), length: ns.length - NSMaxRange(open))
            let close = ns.range(of: "⟧", options: [], range: afterOpen)
            if close.location != NSNotFound {
                selection = NSRange(location: open.location, length: close.location - NSMaxRange(open))
                ns = ns.replacingCharacters(in: close, with: "") as NSString
                ns = ns.replacingCharacters(in: open, with: "") as NSString
            }
        } else {
            let caret = ns.range(of: "‸")
            if caret.location != NSNotFound {
                selection = NSRange(location: caret.location, length: 0)
                ns = ns.replacingCharacters(in: caret, with: "") as NSString
            }
        }
        self.text = ns as String
        self.selection = selection
    }

    mutating func prepend(_ prefix: String) {
        text = prefix + text
        if let current = selection {
            selection = NSRange(location: current.location + (prefix as NSString).length, length: current.length)
        }
    }
}
