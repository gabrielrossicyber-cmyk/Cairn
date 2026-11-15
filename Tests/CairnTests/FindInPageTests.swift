import XCTest
@testable import CairnCore

/// Recherche : ouvrir un résultat de Cmd+K à l'endroit du texte.
final class FindInPageTests: XCTestCase {
    private let text = "---\ntitle: T\n---\n\n# Titre\nPremière ligne sur le réseau\n```bash\nnmap -sV cible\n```\nFin: Réseau local\n"

    private var entry: SearchEntry {
        SearchEntry(url: URL(fileURLWithPath: "/w/Page.md"), title: "Page", fileName: "Page", path: "Page",
                    body: MarkdownPage.parse(text).body, imageLines: ["texte lu dans une image"])
    }

    func testIndexedLinesKeepTheirLineNumber() {
        XCTAssertEqual(entry.lines.prefix(4), ["# Titre", "Première ligne sur le réseau", "nmap -sV cible", "Fin: Réseau local"])
        XCTAssertEqual(entry.lineNumbers, [1, 2, 4, 6, -1])
        XCTAssertEqual(entry.bodyLine(at: 2), 4)
        XCTAssertNil(entry.bodyLine(at: 4), "le texte d'une image n'a pas de ligne dans la page")
        XCTAssertNil(entry.bodyLine(at: 99))
    }

    func testResultsCarryTheLineOfTheirSnippet() {
        XCTAssertEqual(SearchEngine.search("nmap", in: [entry], codeOnly: true).first?.line, 4)
        XCTAssertEqual(SearchEngine.search("reseau local", in: [entry], codeOnly: false).first?.line, 6)
        XCTAssertEqual(SearchEngine.search("premiere", in: [entry], codeOnly: false).first?.line, 2)
        XCTAssertNil(SearchEngine.search("image", in: [entry], codeOnly: false).first?.line)
        XCTAssertNil(SearchEngine.search("", in: [entry], codeOnly: false).first?.line)
    }

    func testEditorRangeOnTheResultLine() throws {
        let ns = text as NSString
        let range = try XCTUnwrap(MarkdownPage.matchRange(of: "reseau", nearBodyLine: 6, in: text))
        XCTAssertEqual(ns.substring(with: range), "Réseau")
        XCTAssertEqual(range.location, ns.range(of: "Fin: ").location + 5)
    }

    func testEditorRangeWithoutLineStartsAtTheFirstMatchOfTheBody() throws {
        let ns = text as NSString
        let range = try XCTUnwrap(MarkdownPage.matchRange(of: "RÉSEAU", nearBodyLine: nil, in: text))
        XCTAssertEqual(ns.substring(with: range), "réseau")
        // Ligne inconnue ou hors de la page : même repli.
        XCTAssertEqual(MarkdownPage.matchRange(of: "reseau", nearBodyLine: 99, in: text), range)
        // Le mot n'est pas sur la ligne annoncée : on le cherche dans le reste de la page.
        XCTAssertEqual(MarkdownPage.matchRange(of: "nmap", nearBodyLine: 1, in: text).map(ns.substring(with:)), "nmap")
    }

    func testEditorRangeFallsBackToSingleWords() throws {
        let ns = text as NSString
        let range = try XCTUnwrap(MarkdownPage.matchRange(of: "local introuvable", nearBodyLine: nil, in: text))
        XCTAssertEqual(ns.substring(with: range), "local")
        XCTAssertEqual(MarkdownPage.matchRange(of: "sV cible", nearBodyLine: 4, in: text).map(ns.substring(with:)), "sV cible")
    }

    func testEditorRangeIgnoresTheHeaderAndEmptyQueries() {
        XCTAssertNil(MarkdownPage.matchRange(of: "title", nearBodyLine: nil, in: text), "l'en-tête n'est pas affiché dans la page")
        XCTAssertNil(MarkdownPage.matchRange(of: "   ", nearBodyLine: nil, in: text))
        XCTAssertNil(MarkdownPage.matchRange(of: "absent", nearBodyLine: 2, in: text))
        XCTAssertNil(MarkdownPage.matchRange(of: "x", nearBodyLine: nil, in: ""))
    }
}
