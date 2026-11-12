import AppKit
import SwiftUI

/// Couleur d'un dossier, enregistrée dans un petit fichier caché `.color` à l'intérieur du dossier.
/// Elle suit donc le dossier quand on le renomme, le déplace ou le duplique, et passe par iCloud.
enum FolderColor: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, mint, teal, blue, indigo, purple, pink, brown, gray

    static let fileName = ".color"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .red: "Rouge"
        case .orange: "Orange"
        case .yellow: "Jaune"
        case .green: "Vert"
        case .mint: "Menthe"
        case .teal: "Bleu-vert"
        case .blue: "Bleu"
        case .indigo: "Indigo"
        case .purple: "Violet"
        case .pink: "Rose"
        case .brown: "Brun"
        case .gray: "Gris"
        }
    }

    /// Couleurs système : elles s'adaptent automatiquement au mode clair / sombre.
    var nsColor: NSColor {
        switch self {
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .mint: .systemMint
        case .teal: .systemTeal
        case .blue: .systemBlue
        case .indigo: .systemIndigo
        case .purple: .systemPurple
        case .pink: .systemPink
        case .brown: .systemBrown
        case .gray: .systemGray
        }
    }

    var color: Color { Color(nsColor: nsColor) }

    /// Pastille colorée pour les menus (une image « non template » garde sa couleur dans un menu macOS).
    var swatch: NSImage {
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            self.nsColor.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    static func read(in folder: URL) -> FolderColor? {
        guard let raw = try? String(contentsOf: folder.appendingPathComponent(fileName), encoding: .utf8) else { return nil }
        return FolderColor(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}
