import XCTest
@testable import CairnCore

/// Index de l'arborescence et historique de navigation du store.
@MainActor
final class StoreNavigationTests: XCTestCase {
    private func makeStore() -> (WikiStore, [URL]) {
        let store = WikiStore(reopensLastWiki: false)
        let root = URL(fileURLWithPath: "/tmp/wiki-nav", isDirectory: true)
        store.rootURL = root
        let a = root.appendingPathComponent("A.md")
        let folder = root.appendingPathComponent("Dossier", isDirectory: true)
        let index = folder.appendingPathComponent("index.md")
        let b = folder.appendingPathComponent("B.md")
        let modeles = root.appendingPathComponent("_Modèles", isDirectory: true)
        store.nodes = [
            WikiNode(id: a, name: "A", isFolder: false, children: nil, pageURL: a),
            WikiNode(id: folder, name: "Dossier", isFolder: true,
                     children: [WikiNode(id: b, name: "B", isFolder: false, children: nil, pageURL: b)], pageURL: index),
            WikiNode(id: modeles, name: "_Modèles", isFolder: true, children: [], pageURL: nil),
        ]
        return (store, [a, folder, b, index])
    }

    func testNodeIndex() {
        let (store, urls) = makeStore()
        XCTAssertEqual(store.node(at: urls[2])?.name, "B")
        XCTAssertEqual(store.node(at: URL(fileURLWithPath: "/tmp/wiki-nav/Dossier/../A.md"))?.name, "A")
        XCTAssertEqual(store.node(forPage: urls[3])?.name, "Dossier", "index.md = page du dossier")
        XCTAssertNil(store.node(at: URL(fileURLWithPath: "/tmp/ailleurs.md")))
        XCTAssertEqual(store.pageOrder, [urls[0], urls[1], urls[2]])
        XCTAssertEqual(store.dashboardFolderOptions.map(\.path), ["Dossier"], "le dossier des modèles n'est pas proposé")
        store.nodes = []
        XCTAssertNil(store.node(at: urls[2]), "index reconstruit quand l'arborescence change")
    }

    func testAdjacentPages() {
        let (store, urls) = makeStore()
        store.goToAdjacentPage(forward: true)
        XCTAssertEqual(store.selection, urls[0])
        store.goToAdjacentPage(forward: true)
        XCTAssertEqual(store.selection, urls[1])
        store.goToAdjacentPage(forward: true)
        store.goToAdjacentPage(forward: true)
        XCTAssertEqual(store.selection, urls[2], "s'arrête à la dernière page")
        store.goToAdjacentPage(forward: false)
        XCTAssertEqual(store.selection, urls[1])
    }

    func testHistoryBackAndForward() {
        let (store, urls) = makeStore()
        for url in [urls[0], urls[1], urls[2]] {
            store.selection = url
            store.recordHistory(url) // ce que fait l'ouverture de la page
        }
        XCTAssertTrue(store.canGoBack)
        XCTAssertFalse(store.canGoForward)

        store.goBack()
        store.recordHistory(store.selection!) // ouverture de la page atteinte : ne doit rien ajouter
        XCTAssertEqual(store.selection, urls[1])
        store.goBack()
        store.recordHistory(store.selection!)
        XCTAssertEqual(store.selection, urls[0])
        XCTAssertFalse(store.canGoBack)
        store.goForward()
        store.recordHistory(store.selection!)
        XCTAssertEqual(store.selection, urls[1])
        XCTAssertTrue(store.canGoForward)

        // Nouvelle page depuis le milieu de l'historique : la suite est oubliée.
        store.selection = urls[2]
        store.recordHistory(urls[2])
        store.goBack()
        store.recordHistory(store.selection!)
        XCTAssertEqual(store.selection, urls[1])
        XCTAssertEqual(store.history, [urls[0], urls[1], urls[2]])
    }
}
