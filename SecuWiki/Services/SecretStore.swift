import AppKit
import Foundation
import Security

/// Secrets dans le Trousseau macOS, utilisés dans les pages avec `{{secret:NOM}}`.
///
/// - Le fichier .md ne contient que la référence `{{secret:NOM}}`, jamais la valeur.
/// - L'aperçu et les PDF affichent « 🔑 NOM » (masqué).
/// - La valeur n'est insérée qu'au moment de copier un bloc de code (bouton « Copier ») :
///   elle va dans le presse-papiers marqué « confidentiel » et est effacée après 60 secondes.
/// - Les secrets restent sur ce Mac (non synchronisés).
enum SecretStore {
    private static let service = "ch.gabriel.cairn.secrets"
    /// Délai avant d'effacer un secret copié.
    static let clipboardLifetime: TimeInterval = 60

    static let didChange = Notification.Name("CairnSecretsDidChange")

    /// `{{secret:NOM}}` (espaces tolérés autour).
    static let pattern = try! NSRegularExpression( // swiftlint:disable:this force_try
        pattern: "\\{\\{\\s*secret:([A-Za-z0-9_\\-]+)\\s*\\}\\}"
    )

    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            (SecCopyErrorMessageString(status, nil) as String?) ?? "Erreur du Trousseau (\(status))."
        }
    }

    static func isValidName(_ name: String) -> Bool {
        name.range(of: "^[A-Za-z0-9_\\-]{1,64}$", options: .regularExpression) != nil
    }

    private static func baseQuery(_ name: String? = nil) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        if let name { query[kSecAttrAccount as String] = name }
        return query
    }

    // MARK: Lire / écrire

    /// Noms des secrets enregistrés (jamais les valeurs).
    static func names() -> [String] {
        var query = baseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func value(_ name: String) -> String? {
        var query = baseQuery(name)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, for name: String) throws {
        let data = Data(value.utf8)
        let status = SecItemUpdate(baseQuery(name) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = baseQuery(name)
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "Cairn : \(name)"
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    static func delete(_ name: String) throws {
        let status = SecItemDelete(baseQuery(name) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    // MARK: Utilisation dans le texte

    static func usedNames(in text: String) -> [String] {
        let ns = text as NSString
        var names: [String] = []
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: match.range(at: 1))
            if !names.contains(name) { names.append(name) }
        }
        return names
    }

    /// Texte avec les valeurs des secrets. `missing` : références sans valeur dans le Trousseau (laissées telles quelles).
    static func resolve(_ text: String) -> (text: String, usedSecret: Bool, missing: [String]) {
        let ns = text as NSString
        let matches = pattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return (text, false, []) }
        let result = NSMutableString(string: text)
        var used = false
        var missing: [String] = []
        for match in matches.reversed() {
            let name = ns.substring(with: match.range(at: 1))
            if let value = value(name) {
                result.replaceCharacters(in: match.range, with: value)
                used = true
            } else if !missing.contains(name) {
                missing.append(name)
            }
        }
        return (result as String, used, missing)
    }

    /// Copie le texte en y insérant les secrets. Si un secret a été inséré, le contenu est marqué
    /// « confidentiel » (ignoré par les gestionnaires de presse-papiers) et effacé après 60 s.
    @discardableResult
    static func copyResolving(_ text: String) -> [String] {
        let (resolved, usedSecret, missing) = resolve(text)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(resolved, forType: .string)
        if usedSecret {
            pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
            let changeCount = pasteboard.changeCount
            DispatchQueue.main.asyncAfter(deadline: .now() + clipboardLifetime) {
                // On n'efface que si personne n'a copié autre chose entre-temps.
                if pasteboard.changeCount == changeCount { pasteboard.clearContents() }
            }
        }
        return missing
    }
}
