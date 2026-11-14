import AppKit
import SwiftUI

/// Réglages de l'app (propres à ce Mac), enregistrés dans les préférences macOS.
enum Prefs {
    // Clés
    static let defaultMode = "defaultMode"
    static let editorFontSize = "editorFontSize"
    static let autosaveDelay = "autosaveDelay"
    static let previewFontSize = "previewFontSize"
    static let previewMaxWidth = "previewMaxWidth"
    static let lineBreaks = "lineBreaks"
    static let autoVerticalDiagrams = "autoVerticalDiagrams"
    static let pdfPaper = "pdfPaper"
    static let pdfShowAnswers = "pdfShowAnswers"
    static let appearance = "appearance"
    static let ocrEnabled = "ocrEnabled"
    static let quickCaptureEnabled = "quickCaptureEnabled"
    static let remoteImages = "remoteImages"

    /// Valeurs par défaut.
    enum Defaults {
        static let defaultMode = EditorMode.preview.rawValue
        static let editorFontSize = 13.0
        static let autosaveDelay = 1.0
        static let previewFontSize = 15.0
        static let previewMaxWidth = 860.0
        static let lineBreaks = true
        static let autoVerticalDiagrams = true
        static let pdfPaper = "A4"
        static let pdfShowAnswers = true
        static let appearance = "system"
        static let ocrEnabled = true
        static let quickCaptureEnabled = true
        /// Images hébergées sur Internet : bloquées par défaut (pas de pistage à l'ouverture d'une page).
        static let remoteImages = false
    }

    /// Applique le thème choisi à toute l'app (fenêtres, éditeur, aperçu).
    /// « system » suit le réglage de macOS, y compris le passage automatique jour / nuit.
    static func applyAppearance(_ value: String) {
        switch value {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    static func double(_ key: String, _ fallback: Double) -> Double {
        UserDefaults.standard.object(forKey: key) as? Double ?? fallback
    }

    static func bool(_ key: String, _ fallback: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
    }

    static func string(_ key: String, _ fallback: String) -> String {
        UserDefaults.standard.string(forKey: key) ?? fallback
    }
}

/// Réglages du wiki, enregistrés dans `.secuwiki.json` à la racine du dossier
/// (synchronisés avec iCloud, donc identiques sur tous tes appareils).
struct WikiSettings: Codable, Equatable {
    /// Nom affiché (vide = nom du dossier).
    var name = ""
    /// Modèle présélectionné à la création d'une page (déclencheur d'une commande « / », vide = page vide).
    var defaultTemplate = ""
    /// Variables disponibles dans toutes les pages ({{NOM}}). Une variable de page est prioritaire.
    var globalVariables: [GlobalVariable] = []
    /// Modèles masqués dans la fenêtre « Nouvelle page ».
    var hiddenTemplates: [String] = []
    /// Widgets du tableau de bord (nil = disposition par défaut).
    var dashboard: [DashboardWidget]?
    /// Examens blancs passés (les 50 derniers).
    var examHistory: [ExamResult] = []

    init() {}

    /// Lecture tolérante : un réglage absent du fichier garde sa valeur par défaut.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        defaultTemplate = try container.decodeIfPresent(String.self, forKey: .defaultTemplate) ?? ""
        globalVariables = try container.decodeIfPresent([GlobalVariable].self, forKey: .globalVariables) ?? []
        hiddenTemplates = try container.decodeIfPresent([String].self, forKey: .hiddenTemplates) ?? []
        // try? : un widget inconnu (version future de l'app) ne doit pas faire perdre les autres réglages.
        dashboard = (try? container.decodeIfPresent([DashboardWidget].self, forKey: .dashboard)) ?? nil
        examHistory = (try? container.decodeIfPresent([ExamResult].self, forKey: .examHistory)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case name, defaultTemplate, globalVariables, hiddenTemplates, dashboard, examHistory
    }

    /// Même contenu (sans tenir compte des identifiants internes des variables).
    func hasSameContent(as other: WikiSettings) -> Bool {
        name == other.name
            && defaultTemplate == other.defaultTemplate
            && hiddenTemplates == other.hiddenTemplates
            && dashboard == other.dashboard
            && examHistory == other.examHistory
            && globalVariables.map { [$0.name, $0.value] } == other.globalVariables.map { [$0.name, $0.value] }
    }
}

struct GlobalVariable: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var value: String

    private enum CodingKeys: String, CodingKey { case name, value }
}

/// Réglages d'affichage de l'aperçu, lus dans les vues (elles se redessinent quand ils changent).
struct PreviewPrefs: DynamicProperty {
    @AppStorage(Prefs.previewFontSize) var fontSize = Prefs.Defaults.previewFontSize
    @AppStorage(Prefs.previewMaxWidth) var maxWidth = Prefs.Defaults.previewMaxWidth
    @AppStorage(Prefs.lineBreaks) var breaks = Prefs.Defaults.lineBreaks
    @AppStorage(Prefs.autoVerticalDiagrams) var autoVertical = Prefs.Defaults.autoVerticalDiagrams
    @AppStorage(Prefs.remoteImages) var remoteImages = Prefs.Defaults.remoteImages

    func context(base: String, pages: [String]) -> RenderContext {
        var context = RenderContext(base: base, pages: pages, fontSize: fontSize, maxWidth: maxWidth,
                                    breaks: breaks, autoVertical: autoVertical)
        context.remoteImages = remoteImages
        return context
    }
}
