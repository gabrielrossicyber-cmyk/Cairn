import SwiftUI

/// Façon d'afficher la page ouverte.
enum EditorMode: String, CaseIterable, Identifiable {
    case preview, edit, split

    var id: String { rawValue }

    var label: String {
        switch self {
        case .preview: return "Lecture"
        case .edit: return "Édition"
        case .split: return "Côte à côte"
        }
    }

    var icon: String {
        switch self {
        case .preview: return "eye"
        case .edit: return "pencil"
        case .split: return "rectangle.split.2x1"
        }
    }
}
