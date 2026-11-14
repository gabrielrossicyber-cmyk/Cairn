import XCTest
@testable import CairnCore

final class PageCryptoTests: XCTestCase {
    private let plain = "---\nid: 1\ntitle: Page test\n---\n\ncontenu secret\n"

    private func sealed() throws -> String {
        try PageCrypto.seal(plain, with: PageCrypto.newSession(password: "motdepasse-test"))
    }

    func testRoundTrip() throws {
        let file = try sealed()
        XCTAssertTrue(PageCrypto.isLocked(file))
        XCTAssertFalse(PageCrypto.isLocked(plain))
        XCTAssertFalse(file.contains("contenu secret"), "le texte ne doit pas rester en clair")
        XCTAssertTrue(file.contains("title: Page test"), "le titre reste lisible pour l'arborescence")
        XCTAssertEqual(try PageCrypto.open(file, password: "motdepasse-test").text, plain)
    }

    func testWrongPasswordIsRejected() throws {
        let file = try sealed()
        XCTAssertThrowsError(try PageCrypto.open(file, password: "autre-mot-de-passe")) { error in
            XCTAssertEqual(error as? PageCrypto.LockError, .wrongPassword)
        }
    }

    func testSessionReopensWithoutPassword() throws {
        let session = try PageCrypto.newSession(password: "motdepasse-test")
        let file = try PageCrypto.seal(plain, with: session)
        XCTAssertEqual(try PageCrypto.open(file, session: session), plain)
        // Chaque enregistrement utilise un nouveau nonce : deux chiffrements du même texte diffèrent.
        XCTAssertNotEqual(file, try PageCrypto.seal(plain, with: session))
    }

    /// Un fichier piégé ne doit ni affaiblir la dérivation de clé ni bloquer l'app (itérations énormes).
    func testTamperedParametersAreRejected() throws {
        let file = try sealed()
        let changes: [(inout [String: Any]) -> Void] = [
            { $0["iter"] = 1_000 },
            { $0["iter"] = 4_000_000_000 },
            { $0["alg"] = "AES-128-ECB" },
            { $0["kdf"] = "MD5" },
            { $0["salt"] = "AAAA" },
            { $0["v"] = 2 },
        ]
        for change in changes {
            let tampered = try rewritingEnvelope(of: file, change)
            XCTAssertThrowsError(try PageCrypto.open(tampered, password: "motdepasse-test")) { error in
                XCTAssertEqual(error as? PageCrypto.LockError, .damaged)
            }
        }
    }

    func testModifiedCiphertextIsDetected() throws {
        let file = try sealed()
        let tampered = try rewritingEnvelope(of: file) { envelope in
            var data = Data(base64Encoded: envelope["data"] as? String ?? "") ?? Data()
            data[data.count - 1] ^= 0x01
            envelope["data"] = data.base64EncodedString()
        }
        XCTAssertThrowsError(try PageCrypto.open(tampered, password: "motdepasse-test"))
    }

    /// Décode le bloc chiffré, applique une modification, et le remet dans le fichier.
    private func rewritingEnvelope(of file: String, _ change: (inout [String: Any]) -> Void) throws -> String {
        let start = try XCTUnwrap(file.range(of: "\n```cairn-locked\n"))
        let end = try XCTUnwrap(file.range(of: "\n```", range: start.upperBound..<file.endIndex))
        let base64 = String(file[start.upperBound..<end.lowerBound].filter { !$0.isWhitespace })
        let decoded = try XCTUnwrap(Data(base64Encoded: base64))
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: decoded) as? [String: Any])
        change(&envelope)
        let encoded = try JSONSerialization.data(withJSONObject: envelope).base64EncodedString()
        return file.replacingCharacters(in: start.upperBound..<end.lowerBound, with: encoded)
    }
}
