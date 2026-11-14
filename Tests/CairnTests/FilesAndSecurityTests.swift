import XCTest
@testable import CairnCore

final class FilesAndSecurityTests: XCTestCase {
    private var sandbox: URL!
    private var root: URL!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("CairnTests-" + UUID().uuidString, isDirectory: true)
        root = sandbox.appendingPathComponent("wiki", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        WikiAssetSchemeHandler.rootURL = nil
        try? FileManager.default.removeItem(at: sandbox)
    }

    private func write(_ text: String, _ path: String, in folder: URL? = nil) throws {
        let url = (folder ?? root).appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func asset(_ path: String) throws -> URL {
        try XCTUnwrap(URL(string: WikiAssetSchemeHandler.scheme + "://" + path))
    }

    // MARK: Fichiers servis à l'aperçu

    func testOnlyFilesInsideTheWikiAreServed() throws {
        try write("image", "assets/a.png")
        try write("secret", "secret.txt", in: sandbox)
        try write("autre", "a.png", in: sandbox.appendingPathComponent("wiki-voisin"))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("lien.txt"),
            withDestinationURL: sandbox.appendingPathComponent("secret.txt")
        )
        WikiAssetSchemeHandler.rootURL = root

        XCTAssertNotNil(WikiAssetSchemeHandler.safeFileURL(for: try asset(root.path + "/assets/a.png")))
        // « .. », dossier voisin au nom proche, lien symbolique vers l'extérieur : refusés.
        XCTAssertNil(WikiAssetSchemeHandler.safeFileURL(for: try asset(root.path + "/../secret.txt")))
        XCTAssertNil(WikiAssetSchemeHandler.safeFileURL(for: try asset(root.path + "/assets/../../secret.txt")))
        XCTAssertNil(WikiAssetSchemeHandler.safeFileURL(for: try asset(sandbox.path + "/wiki-voisin/a.png")))
        XCTAssertNil(WikiAssetSchemeHandler.safeFileURL(for: try asset(root.path + "/lien.txt")))
        XCTAssertNil(WikiAssetSchemeHandler.safeFileURL(for: try asset("/etc/passwd")))
    }

    func testNothingIsServedWithoutAnOpenWiki() throws {
        WikiAssetSchemeHandler.rootURL = nil
        XCTAssertNil(WikiAssetSchemeHandler.safeFileURL(for: try asset("/etc/passwd")))
    }

    func testExecutablesAreNeverOpened() {
        for name in ["doc.pdf", "capture.png", "notes.txt"] {
            XCTAssertTrue(WikiAssetSchemeHandler.isSafeToOpen(URL(fileURLWithPath: "/w/" + name)), name)
        }
        for name in ["outil.app", "script.sh", "lancer.command", "paquet.pkg", "image.dmg", "macro.scpt"] {
            XCTAssertFalse(WikiAssetSchemeHandler.isSafeToOpen(URL(fileURLWithPath: "/w/" + name)), name)
        }
    }

    func testActiveContentIsServedAsPlainText() {
        for name in ["page.html", "page.HTM", "code.js", "data.xml"] {
            XCTAssertEqual(WikiAssetSchemeHandler.servedMIMEType(for: URL(fileURLWithPath: "/w/" + name)), "text/plain", name)
        }
        XCTAssertEqual(WikiAssetSchemeHandler.servedMIMEType(for: URL(fileURLWithPath: "/w/a.png")), "image/png")
        XCTAssertEqual(WikiAssetSchemeHandler.servedMIMEType(for: URL(fileURLWithPath: "/w/a.pdf")), "application/pdf")
    }

    // MARK: Import HTML

    func testImportedHTMLIsNeutralized() {
        let html = """
        <p>ok</p><script>alert(1)</script><img src="https://t.ch/p.png">
        <iframe src="https://t.ch"></iframe><a style="background:url(https://t.ch/x)">lien</a>
        <link rel="stylesheet" href="https://t.ch/s.css">
        """
        let result = WikiStore.neutralizedHTML(html)
        XCTAssertTrue(result.contains("<p>ok</p>"))
        for forbidden in ["<script", "alert(1)", "<iframe", "<link", " src=", "url("] {
            XCTAssertFalse(result.contains(forbidden), forbidden)
        }
        XCTAssertTrue(result.contains("data-blocked-src="))
    }

    // MARK: Arborescence

    func testScanBuildsTheTreeAndFollowsOrderFile() throws {
        try write("b", "B.md")
        try write("a", "A.md")
        try write("page du dossier", "Dossier/index.md")
        try write("p", "Dossier/Page.md")
        try write("ignoré", "assets/x.md")
        try write("caché", ".cache.md")
        try write("pas une page", "notes.txt")

        var nodes = WikiScanner.scan(folder: root)
        XCTAssertEqual(nodes.map(\.name), ["A", "B", "Dossier"])
        let folder = try XCTUnwrap(nodes.last)
        XCTAssertTrue(folder.isFolder)
        XCTAssertEqual(folder.pageURL?.lastPathComponent, "index.md")
        XCTAssertEqual(folder.children?.map(\.name), ["Page"])

        try OrderFile.write(["Dossier", "B"], in: root)
        nodes = WikiScanner.scan(folder: root)
        XCTAssertEqual(nodes.map(\.name), ["Dossier", "B", "A"])
    }

    func testOrderFileAppendAndRemove() throws {
        XCTAssertNil(OrderFile.read(in: root))
        OrderFile.append("A", in: root) // pas de .order : rien n'est créé
        XCTAssertNil(OrderFile.read(in: root))
        try OrderFile.write(["A"], in: root)
        OrderFile.append("B", in: root)
        OrderFile.append("B", in: root)
        XCTAssertEqual(OrderFile.read(in: root), ["A", "B"])
        OrderFile.rename("A", to: "C", in: root)
        OrderFile.remove("B", in: root)
        XCTAssertEqual(OrderFile.read(in: root), ["C"])
    }

    // MARK: Wikis

    func testDeletedOrTrashedWikiIsUnavailable() {
        XCTAssertFalse(FolderAccess.isUnavailable(root))
        XCTAssertTrue(FolderAccess.isUnavailable(sandbox.appendingPathComponent("supprimé")))
        XCTAssertTrue(FolderAccess.isInTrash("/Users/gabriel/.Trash/BF-CYBER"))
        XCTAssertTrue(FolderAccess.isInTrash("/Volumes/Disque/.Trashes/501/BF-CYBER"))
        XCTAssertFalse(FolderAccess.isInTrash("/Users/gabriel/Documents/BF-CYBER"))
    }

    func testGuideIsCreatedOnceAndNeverOverwritten() throws {
        let url = try WikiStore.writeGuide(in: root)
        let content = try String(contentsOf: url, encoding: .utf8)
        let page = MarkdownPage.parse(content)
        XCTAssertEqual(url.lastPathComponent, "Guide-Cairn.md")
        XCTAssertEqual(page.frontMatter["title"], "Guide Cairn")
        XCTAssertEqual(page.variables.map(\.name), ["IP_CIBLE"])
        XCTAssertEqual(MarkdownPage.tags(in: content).first, "guide")

        try "mes modifications".write(to: url, atomically: true, encoding: .utf8)
        try WikiStore.writeGuide(in: root)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "mes modifications")
    }
}
