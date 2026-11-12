import Foundation

/// Un widget du tableau de bord. La liste est enregistrée dans .secuwiki.json (une disposition par wiki).
struct DashboardWidget: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case stats, countdown, question, tasks, recent, favorites, folder, sections, note

        var id: String { rawValue }

        var label: String {
            switch self {
            case .stats: "Chiffres clés"
            case .countdown: "Compte à rebours"
            case .question: "Question de révision au hasard"
            case .tasks: "À faire"
            case .recent: "Modifiées récemment"
            case .favorites: "Favoris"
            case .folder: "Contenu d'un dossier"
            case .sections: "Pages par section"
            case .note: "Note libre"
            }
        }

        var icon: String {
            switch self {
            case .stats: "number"
            case .countdown: "calendar.badge.clock"
            case .question: "questionmark.bubble"
            case .tasks: "checklist"
            case .recent: "clock"
            case .favorites: "star"
            case .folder: "folder"
            case .sections: "chart.bar"
            case .note: "note.text"
            }
        }

        /// Pleine largeur par défaut ?
        var defaultWide: Bool { self == .stats || self == .tasks }

        /// Le widget a-t-il un nombre d'éléments réglable ?
        var hasLimit: Bool { [.tasks, .recent, .favorites, .folder].contains(self) }
    }

    var id = UUID()
    var kind: Kind
    /// Pleine largeur (sinon une demi-colonne, deux widgets côte à côte).
    var wide: Bool
    /// Titre personnalisé (vide = titre par défaut).
    var title = ""
    /// Note libre (Markdown simple : **gras**, *italique*, `code`, liens).
    var text = ""
    /// Compte à rebours : date cible.
    var date: Date?
    /// Dossier (chemin relatif à la racine) : contenu d'un dossier, ou filtre des tâches.
    var folder = ""
    /// Nombre d'éléments affichés (listes).
    var limit = 8

    init(kind: Kind) {
        self.kind = kind
        self.wide = kind.defaultWide
        if kind == .countdown {
            title = "Examen du brevet"
            date = Calendar.current.date(byAdding: .month, value: 18, to: .now)
        }
        if kind == .note { text = "Écris ici ce que tu veux garder sous les yeux." }
    }

    var displayTitle: String { title.trimmingCharacters(in: .whitespaces).isEmpty ? kind.label : title }

    /// Disposition proposée tant que l'utilisateur n'a rien personnalisé.
    static var defaultLayout: [DashboardWidget] {
        [.init(kind: .stats), .init(kind: .sections), .init(kind: .recent), .init(kind: .tasks)]
    }

    // Lecture tolérante : un champ absent garde sa valeur par défaut.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        wide = try container.decodeIfPresent(Bool.self, forKey: .wide) ?? kind.defaultWide
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        date = try container.decodeIfPresent(Date.self, forKey: .date)
        folder = try container.decodeIfPresent(String.self, forKey: .folder) ?? ""
        limit = try container.decodeIfPresent(Int.self, forKey: .limit) ?? 8
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, wide, title, text, date, folder, limit
    }
}
