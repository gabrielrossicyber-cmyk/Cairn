import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Une combinaison de touches : une touche + des modificateurs (⌘ ⇧ ⌥ ⌃).
struct KeyCombo: Codable, Hashable {
    /// Caractère en minuscule (« n », « 1 », « , ») ou nom d'une touche spéciale (« return », « up », « f5 »…).
    var key: String
    var command = false
    var shift = false
    var option = false
    var control = false
    /// Code physique de la touche (nécessaire au raccourci global, qui passe par Carbon).
    var keyCode: Int?

    init(_ key: String, command: Bool = true, shift: Bool = false, option: Bool = false, control: Bool = false,
         keyCode: Int? = nil) {
        self.key = key.lowercased()
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
        self.keyCode = keyCode
    }

    /// Même touches (le code physique n'entre pas en compte : « N » reste « N » sur tous les claviers).
    func sameKeys(as other: KeyCombo) -> Bool {
        key == other.key && command == other.command && shift == other.shift
            && option == other.option && control == other.control
    }

    private static let specialKeys: [String: (equivalent: KeyEquivalent, symbol: String)] = [
        "return": (.return, "↩"), "tab": (.tab, "⇥"), "space": (.space, "Espace"),
        "delete": (.delete, "⌫"), "forwarddelete": (.deleteForward, "⌦"), "escape": (.escape, "⎋"),
        "up": (.upArrow, "↑"), "down": (.downArrow, "↓"), "left": (.leftArrow, "←"), "right": (.rightArrow, "→"),
        "home": (.home, "↖"), "end": (.end, "↘"), "pageup": (.pageUp, "⇞"), "pagedown": (.pageDown, "⇟"),
    ]

    private var functionNumber: Int? {
        guard key.count >= 2, key.hasPrefix("f"), let number = Int(key.dropFirst()), (1...20).contains(number) else { return nil }
        return number
    }

    var isFunctionKey: Bool { functionNumber != nil }

    /// Raccourci SwiftUI (menus). nil si la touche n'est pas représentable.
    var keyboardShortcut: KeyboardShortcut? {
        var modifiers: SwiftUI.EventModifiers = []
        if command { modifiers.insert(.command) }
        if shift { modifiers.insert(.shift) }
        if option { modifiers.insert(.option) }
        if control { modifiers.insert(.control) }
        if let special = Self.specialKeys[key] {
            return KeyboardShortcut(special.equivalent, modifiers: modifiers)
        }
        if let number = functionNumber, let scalar = Unicode.Scalar(NSF1FunctionKey + number - 1) {
            return KeyboardShortcut(KeyEquivalent(Character(scalar)), modifiers: modifiers)
        }
        guard key.count == 1, let character = key.first else { return nil }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: modifiers)
    }

    /// Affichage façon macOS : ⌃⌥⇧⌘N.
    var display: String {
        var text = ""
        if control { text += "⌃" }
        if option { text += "⌥" }
        if shift { text += "⇧" }
        if command { text += "⌘" }
        if let special = Self.specialKeys[key] { return text + special.symbol }
        return text + key.uppercased()
    }

    /// Affichage en toutes lettres, pour les bulles d'aide : « Cmd+Maj+N ».
    var spelledOut: String {
        var parts: [String] = []
        if control { parts.append("Ctrl") }
        if option { parts.append("Option") }
        if shift { parts.append("Maj") }
        if command { parts.append("Cmd") }
        if let special = Self.specialKeys[key] { parts.append(special.symbol) } else { parts.append(key.uppercased()) }
        return parts.joined(separator: "+")
    }

    /// Un raccourci doit utiliser ⌘ ou ⌃ (sinon il empêcherait de taper du texte), sauf une touche F1…F20.
    var isUsable: Bool { command || control || isFunctionKey }

    /// Modificateurs au format Carbon (raccourci global).
    var carbonModifiers: Int {
        (command ? cmdKey : 0) | (shift ? shiftKey : 0) | (option ? optionKey : 0) | (control ? controlKey : 0)
    }

    // MARK: Lecture d'une frappe

    private static let specialKeyCodes: [Int: String] = [
        kVK_Return: "return", kVK_ANSI_KeypadEnter: "return", kVK_Tab: "tab", kVK_Space: "space",
        kVK_Delete: "delete", kVK_ForwardDelete: "forwarddelete", kVK_Escape: "escape",
        kVK_UpArrow: "up", kVK_DownArrow: "down", kVK_LeftArrow: "left", kVK_RightArrow: "right",
        kVK_Home: "home", kVK_End: "end", kVK_PageUp: "pageup", kVK_PageDown: "pagedown",
        kVK_F1: "f1", kVK_F2: "f2", kVK_F3: "f3", kVK_F4: "f4", kVK_F5: "f5", kVK_F6: "f6",
        kVK_F7: "f7", kVK_F8: "f8", kVK_F9: "f9", kVK_F10: "f10", kVK_F11: "f11", kVK_F12: "f12",
        kVK_F13: "f13", kVK_F14: "f14", kVK_F15: "f15", kVK_F16: "f16", kVK_F17: "f17",
        kVK_F18: "f18", kVK_F19: "f19", kVK_F20: "f20",
    ]

    /// Combinaison tapée au clavier (enregistreur des Réglages). nil pour une touche seule de modification.
    init?(event: NSEvent) {
        let code = Int(event.keyCode)
        let key: String
        if let special = Self.specialKeyCodes[code] {
            key = special
        } else if let base = event.characters(byApplyingModifiers: [])?.lowercased(),
                  base.count == 1, let scalar = base.unicodeScalars.first,
                  !CharacterSet.controlCharacters.contains(scalar) {
            // Caractère de la touche sans ⇧ ni ⌥ : « 1 » et non « + », « n » et non « ~ ».
            key = base
        } else {
            return nil
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        self.init(key, command: flags.contains(.command), shift: flags.contains(.shift),
                  option: flags.contains(.option), control: flags.contains(.control), keyCode: code)
    }
}

/// Une action qui a un raccourci réglable (Réglages › Raccourcis).
enum ShortcutAction: String, CaseIterable, Identifiable, Codable {
    // Fichier
    case newPage, newFolder, importDocuments, newWiki, openWiki, save, exportPDF, printPage, exportWiki
    // Format
    case bold, italic, inlineCode, insertTable, insertCode
    // Page
    case search, dashboard, exam, linkMap, modePreview, modeEdit, modeSplit, outline, focusMode, favorite, lock, reload
    // Partout
    case quickCapture

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newPage: "Nouvelle page"
        case .newFolder: "Nouveau dossier"
        case .importDocuments: "Importer des documents"
        case .newWiki: "Nouveau wiki"
        case .openWiki: "Ouvrir un wiki existant"
        case .save: "Enregistrer"
        case .exportPDF: "Exporter la page en PDF"
        case .printPage: "Imprimer"
        case .exportWiki: "Exporter tout le wiki (.zip)"
        case .bold: "Gras"
        case .italic: "Italique"
        case .inlineCode: "Code"
        case .insertTable: "Insérer un tableau"
        case .insertCode: "Insérer une commande bash"
        case .search: "Rechercher dans le wiki"
        case .dashboard: "Tableau de bord"
        case .exam: "Mode examen"
        case .linkMap: "Carte des liens"
        case .modePreview: "Mode Lecture"
        case .modeEdit: "Mode Édition"
        case .modeSplit: "Mode Côte à côte"
        case .outline: "Sommaire"
        case .focusMode: "Mode concentration"
        case .favorite: "Ajouter / retirer des favoris"
        case .lock: "Verrouiller la page"
        case .reload: "Rafraîchir"
        case .quickCapture: "Capture rapide"
        }
    }

    enum Group: String, CaseIterable {
        case file = "Fichier"
        case format = "Format (éditeur)"
        case page = "Page"
        case global = "Partout, même quand Cairn n'est pas au premier plan"
    }

    var group: Group {
        switch self {
        case .newPage, .newFolder, .importDocuments, .newWiki, .openWiki, .save, .exportPDF, .printPage, .exportWiki: .file
        case .bold, .italic, .inlineCode, .insertTable, .insertCode: .format
        case .quickCapture: .global
        default: .page
        }
    }

    /// Raccourci global (Carbon) plutôt qu'un raccourci de menu.
    var isGlobal: Bool { self == .quickCapture }

    var defaultCombo: KeyCombo {
        switch self {
        case .newPage: KeyCombo("n")
        case .newFolder: KeyCombo("n", shift: true)
        case .importDocuments: KeyCombo("i", shift: true)
        case .newWiki: KeyCombo("n", option: true)
        case .openWiki: KeyCombo("o")
        case .save: KeyCombo("s")
        case .exportPDF: KeyCombo("e", shift: true)
        case .printPage: KeyCombo("p")
        case .exportWiki: KeyCombo("e", option: true)
        case .bold: KeyCombo("b")
        case .italic: KeyCombo("i")
        case .inlineCode: KeyCombo("c", shift: true)
        case .insertTable: KeyCombo("t", option: true)
        case .insertCode: KeyCombo("c", option: true)
        case .search: KeyCombo("k")
        case .dashboard: KeyCombo("d", shift: true)
        case .exam: KeyCombo("x", shift: true)
        case .linkMap: KeyCombo("m", shift: true)
        case .modePreview: KeyCombo("1")
        case .modeEdit: KeyCombo("2")
        case .modeSplit: KeyCombo("3")
        case .outline: KeyCombo("o", shift: true)
        case .focusMode: KeyCombo("f", shift: true)
        case .favorite: KeyCombo("d")
        case .lock: KeyCombo("l")
        case .reload: KeyCombo("r")
        case .quickCapture: KeyCombo("n", command: false, option: true, control: true, keyCode: kVK_ANSI_N)
        }
    }
}

extension EditorMode {
    var shortcutAction: ShortcutAction {
        switch self {
        case .preview: .modePreview
        case .edit: .modeEdit
        case .split: .modeSplit
        }
    }
}

/// Raccourcis personnalisés, enregistrés dans les préférences de ce Mac (JSON).
/// Seules les différences avec les raccourcis par défaut sont gardées.
struct ShortcutSettings: Codable, Equatable {
    /// Raccourcis modifiés, par action.
    var custom: [String: KeyCombo] = [:]
    /// Actions dont le raccourci a été retiré.
    var disabled: [String] = []

    /// Raccourcis de macOS et de l'édition de texte : jamais attribués à une action de Cairn.
    static let reserved: [KeyCombo] = [
        KeyCombo("q"), KeyCombo("w"), KeyCombo("h"), KeyCombo("m"), KeyCombo(","),
        KeyCombo("z"), KeyCombo("z", shift: true), KeyCombo("x"), KeyCombo("c"), KeyCombo("v"), KeyCombo("a"),
        KeyCombo("f"), KeyCombo("g"), KeyCombo("g", shift: true), KeyCombo("h", option: true),
        KeyCombo("tab"), KeyCombo("space"), KeyCombo("space", command: false, control: true), KeyCombo("`"),
        KeyCombo("q", control: true), KeyCombo("f", control: true), KeyCombo("3", shift: true),
        KeyCombo("4", shift: true), KeyCombo("5", shift: true), KeyCombo("escape", option: true),
    ]

    // MARK: Lecture

    static func load(from json: String) -> ShortcutSettings {
        guard !json.isEmpty, let data = json.data(using: .utf8),
              let settings = try? JSONDecoder().decode(ShortcutSettings.self, from: data) else { return ShortcutSettings() }
        return settings
    }

    /// Réglages actuels (lus dans les préférences).
    static var current: ShortcutSettings {
        load(from: UserDefaults.standard.string(forKey: Prefs.shortcuts) ?? "")
    }

    var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(self) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Combinaison active (nil = aucun raccourci).
    func combo(for action: ShortcutAction) -> KeyCombo? {
        if disabled.contains(action.rawValue) { return nil }
        return custom[action.rawValue] ?? action.defaultCombo
    }

    func shortcut(for action: ShortcutAction) -> KeyboardShortcut? {
        combo(for: action)?.keyboardShortcut
    }

    /// « Rechercher (Cmd+K) » pour les bulles d'aide ; le titre seul s'il n'y a pas de raccourci.
    func help(_ text: String, _ action: ShortcutAction) -> String {
        guard let combo = combo(for: action) else { return text }
        return "\(text) (\(combo.spelledOut))"
    }

    func isDefault(_ action: ShortcutAction) -> Bool {
        custom[action.rawValue] == nil && !disabled.contains(action.rawValue)
    }

    var hasChanges: Bool { !custom.isEmpty || !disabled.isEmpty }

    // MARK: Vérifications

    enum Problem: Equatable {
        case unusable
        case reserved
        case usedBy(ShortcutAction)
    }

    /// Ce qui empêche (ou demande confirmation pour) d'attribuer cette combinaison à cette action.
    func problem(with combo: KeyCombo, for action: ShortcutAction) -> Problem? {
        if !combo.isUsable { return .unusable }
        if Self.reserved.contains(where: { $0.sameKeys(as: combo) }) { return .reserved }
        if let other = self.action(using: combo), other != action { return .usedBy(other) }
        return nil
    }

    /// Action qui utilise déjà cette combinaison.
    func action(using combo: KeyCombo) -> ShortcutAction? {
        ShortcutAction.allCases.first { self.combo(for: $0)?.sameKeys(as: combo) == true }
    }

    // MARK: Modification

    /// Attribue une combinaison (nil = retirer le raccourci). Revenir au raccourci par défaut efface la personnalisation.
    mutating func set(_ combo: KeyCombo?, for action: ShortcutAction) {
        custom[action.rawValue] = nil
        disabled.removeAll { $0 == action.rawValue }
        guard let combo else {
            disabled.append(action.rawValue)
            disabled.sort()
            return
        }
        if !combo.sameKeys(as: action.defaultCombo) || (action.isGlobal && combo.keyCode != action.defaultCombo.keyCode) {
            custom[action.rawValue] = combo
        }
    }

    mutating func reset(_ action: ShortcutAction) {
        custom[action.rawValue] = nil
        disabled.removeAll { $0 == action.rawValue }
    }
}
