import XCTest
@testable import CairnCore

final class SearchAndTextTests: XCTestCase {

    private var entries: [SearchEntry] {
        [
            SearchEntry(url: URL(fileURLWithPath: "/w/Nmap.md"), title: "Nmap", fileName: "Nmap",
                        path: "Réseau › Nmap",
                        body: "Scan de ports\n```bash\nnmap -sV cible\n```\nVoir [[Wireshark|l'outil]]",
                        tags: ["réseau"]),
            SearchEntry(url: URL(fileURLWithPath: "/w/Wireshark.md"), title: "Wireshark", fileName: "Wireshark",
                        path: "Outils › Wireshark", body: "Capture de trames réseau"),
        ]
    }

    func testSearchIgnoresAccentsAndRanksPathAboveText() {
        let results = SearchEngine.search("reseau", in: entries, codeOnly: false)
        XCTAssertEqual(results.map(\.entry.title), ["Nmap", "Wireshark"])
    }

    func testAllWordsMustMatch() {
        XCTAssertEqual(SearchEngine.search("capture trames", in: entries, codeOnly: false).map(\.entry.title), ["Wireshark"])
        XCTAssertTrue(SearchEngine.search("capture nmap", in: entries, codeOnly: false).isEmpty)
    }

    func testCodeOnlySearch() {
        let results = SearchEngine.search("nmap", in: entries, codeOnly: true)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.snippet, "nmap -sV cible")
        XCTAssertEqual(results.first?.snippetIsCode, true)
        XCTAssertTrue(SearchEngine.search("scan", in: entries, codeOnly: true).isEmpty)
    }

    func testEmptyQueryListsAllPages() {
        XCTAssertEqual(SearchEngine.search("", in: entries, codeOnly: false).map(\.entry.title), ["Nmap", "Wireshark"])
    }

    func testEntryLinksAndKeys() {
        XCTAssertEqual(entries[0].links, ["wireshark"])
        XCTAssertEqual(entries[0].keys, ["nmap"])
        XCTAssertEqual(entries[0].tagKeys, ["reseau"])
    }

    func testNormalizeAndTemplatesFolder() {
        XCTAssertEqual(SearchEngine.normalize("Éléphant"), "elephant")
        XCTAssertTrue(SearchEngine.isTemplatesFolder("_Modèles"))
        XCTAssertFalse(SearchEngine.isTemplatesFolder("Modules"))
    }

    func testRenamingAPageUpdatesLinksOutsideCode() {
        let text = "Voir [[Ancien nom]] et [[ancien nom|alias]]\n```\n[[Ancien nom]]\n```"
        let result = LinkUpdater.replacingLinks(in: text, oldKeys: ["ancien nom"], newName: "Nouveau")
        XCTAssertEqual(result.text, "Voir [[Nouveau]] et [[Nouveau|alias]]\n```\n[[Ancien nom]]\n```")
        XCTAssertEqual(result.count, 2)
    }

    func testFileNames() throws {
        XCTAssertEqual(try FileNaming.fileName(from: "Lab Nmap : scan SYN"), "Lab-Nmap-scan-SYN")
        // Un titre ne peut pas sortir du dossier ni créer un fichier caché.
        let hostile = try FileNaming.fileName(from: "../../etc/passwd")
        XCTAssertFalse(hostile.contains("/"))
        XCTAssertFalse(hostile.hasPrefix("."))
        XCTAssertThrowsError(try FileNaming.fileName(from: "???"))
    }

    func testTables() {
        XCTAssertEqual(TableFormatter.cells(of: "| a | b |"), ["a", "b"])
        XCTAssertTrue(TableFormatter.isSeparator(["---", ":---:"]))
        XCTAssertFalse(TableFormatter.isSeparator(["a", "---"]))
        let layout = TableFormatter.layout(rows: [["Port", "Service"], ["---", "---"], ["22", "SSH"]])
        let widths = Set(layout.text.components(separatedBy: "\n").map(\.count))
        XCTAssertEqual(widths.count, 1, "toutes les lignes d'un tableau aligné ont la même largeur")
    }

    func testSwissGrades() {
        XCTAssertEqual(ExamGrading.swissGrade(points: 6, total: 6), 6)
        XCTAssertEqual(ExamGrading.swissGrade(points: 0, total: 6), 1)
        XCTAssertEqual(ExamGrading.swissGrade(points: 3, total: 6), 3.5)
        XCTAssertEqual(ExamGrading.swissGrade(points: 99, total: 6), 6)
        XCTAssertEqual(ExamGrading.swissGrade(points: 2, total: 0), 1)
        XCTAssertEqual(ExamGrading.format(4), "4")
        XCTAssertEqual(ExamGrading.format(4.5), "4.5")
    }

    func testSecretNames() {
        XCTAssertTrue(SecretStore.isValidName("ADMIN_DC01"))
        XCTAssertFalse(SecretStore.isValidName("mot de passe"))
        XCTAssertFalse(SecretStore.isValidName(""))
        XCTAssertFalse(SecretStore.isValidName("a}}{{secret:b"))
    }
}
