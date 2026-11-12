import Foundation
import CryptoKit
import CommonCrypto

/// Clé d'une page déverrouillée, gardée en mémoire seulement (jamais écrite sur le disque).
struct LockSession {
    let key: SymmetricKey
    let salt: Data
    let iterations: Int
}

/// Chiffrement des pages verrouillées.
///
/// - Dérivation : PBKDF2-HMAC-SHA256, 600 000 itérations (recommandation OWASP), sel aléatoire de 16 octets.
/// - Chiffrement : AES-256-GCM (CryptoKit), nonce aléatoire à chaque enregistrement.
///   GCM authentifie le contenu : un mauvais mot de passe ou un fichier modifié est détecté.
///
/// Le fichier reste un .md lisible ailleurs : un en-tête en clair (id, titre, dates, `locked: true`),
/// une note explicative, puis le contenu chiffré dans un bloc ```cairn-locked.
/// Tout le reste (texte, variables, en-tête complet) est chiffré.
enum PageCrypto {
    static let iterations = 600_000
    static let minimumPasswordLength = 8
    private static let fence = "```cairn-locked"

    enum LockError: LocalizedError {
        case wrongPassword, damaged, keyDerivation

        var errorDescription: String? {
            switch self {
            case .wrongPassword: "Mot de passe incorrect."
            case .damaged: "Le contenu chiffré de cette page est endommagé."
            case .keyDerivation: "Impossible de préparer la clé de chiffrement."
            }
        }
    }

    /// Format du bloc chiffré (JSON encodé en base64).
    private struct Envelope: Codable {
        var v = 1
        var alg = "AES-256-GCM"
        var kdf = "PBKDF2-SHA256"
        var iter: Int
        var salt: String
        /// nonce (12 o) + texte chiffré + tag (16 o), en base64.
        var data: String
    }

    // MARK: Détection

    static func isLocked(_ text: String) -> Bool {
        text.contains("\n" + fence + "\n")
    }

    // MARK: Clés

    /// Dérive une clé de 256 bits du mot de passe. Volontairement lent (≈ 0,3 s) : à appeler hors du fil principal.
    static func deriveKey(password: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        let normalized = password.precomposedStringWithCanonicalMapping
        var derived = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { (saltBytes: UnsafeRawBufferPointer) -> Int32 in
            derived.withUnsafeMutableBufferPointer { output in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    normalized, normalized.utf8.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations),
                    output.baseAddress, 32
                )
            }
        }
        guard status == Int32(kCCSuccess) else { throw LockError.keyDerivation }
        defer { for index in derived.indices { derived[index] = 0 } } // efface la copie locale
        return SymmetricKey(data: derived)
    }

    /// Nouvelle session (nouveau sel) pour verrouiller une page.
    static func newSession(password: String) throws -> LockSession {
        let salt = SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
        return LockSession(key: try deriveKey(password: password, salt: salt, iterations: iterations),
                           salt: salt, iterations: iterations)
    }

    // MARK: Chiffrer

    /// Contenu du fichier verrouillé à partir du texte en clair de la page.
    static func seal(_ plain: String, with session: LockSession) throws -> String {
        let box = try AES.GCM.seal(Data(plain.utf8), using: session.key)
        guard let combined = box.combined else { throw LockError.damaged }
        let envelope = Envelope(iter: session.iterations,
                                salt: session.salt.base64EncodedString(),
                                data: combined.base64EncodedString())
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let armored = try encoder.encode(envelope)
            .base64EncodedString(options: [.lineLength76Characters, .endLineWithLineFeed])

        // En-tête en clair : de quoi afficher la page dans l'arborescence et la recherche, rien de plus.
        let page = MarkdownPage.parse(plain)
        var header = "---\n"
        for key in ["id", "title", "created", "updated"] {
            if let value = page.frontMatter[key], !value.isEmpty {
                header += "\(key): \(MarkdownPage.yamlValue(value))\n"
            }
        }
        header += "locked: true\n---\n\n"

        return header
            + "> [!ATTENTION]\n"
            + "> Page verrouillée par Cairn (AES-256-GCM). Ouvre-la dans Cairn avec son mot de passe.\n\n"
            + fence + "\n" + armored + "\n```\n"
    }

    // MARK: Déchiffrer

    /// Déchiffre avec le mot de passe ; retourne le texte et la session à garder en mémoire.
    static func open(_ fileText: String, password: String) throws -> (text: String, session: LockSession) {
        let envelope = try readEnvelope(fileText)
        guard let salt = Data(base64Encoded: envelope.salt) else { throw LockError.damaged }
        let session = LockSession(key: try deriveKey(password: password, salt: salt, iterations: envelope.iter),
                                  salt: salt, iterations: envelope.iter)
        return (try decrypt(envelope, key: session.key), session)
    }

    /// Déchiffre avec une session déjà ouverte (pas de nouvelle saisie du mot de passe).
    static func open(_ fileText: String, session: LockSession) throws -> String {
        let envelope = try readEnvelope(fileText)
        guard Data(base64Encoded: envelope.salt) == session.salt else { throw LockError.wrongPassword }
        return try decrypt(envelope, key: session.key)
    }

    private static func decrypt(_ envelope: Envelope, key: SymmetricKey) throws -> String {
        guard let combined = Data(base64Encoded: envelope.data) else { throw LockError.damaged }
        let plain: Data
        do {
            plain = try AES.GCM.open(try AES.GCM.SealedBox(combined: combined), using: key)
        } catch {
            throw LockError.wrongPassword // tag GCM invalide : mauvaise clé (ou fichier altéré)
        }
        guard let text = String(data: plain, encoding: .utf8) else { throw LockError.damaged }
        return text
    }

    private static func readEnvelope(_ text: String) throws -> Envelope {
        guard let start = text.range(of: "\n" + fence + "\n"),
              let end = text.range(of: "\n```", range: start.upperBound..<text.endIndex)
        else { throw LockError.damaged }
        let base64 = text[start.upperBound..<end.lowerBound].filter { !$0.isWhitespace }
        guard let json = Data(base64Encoded: String(base64)),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: json),
              envelope.v == 1
        else { throw LockError.damaged }
        return envelope
    }
}
