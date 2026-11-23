import XCTest
@testable import CairnCore

/// Optimisations (mêmes résultats qu'avant, en plus rapide) et navigation au clavier.
final class PerformanceAndNavigationTests: XCTestCase {

    func testHeaderLineCountMatchesTheSlowVersion() {
        for text in ["", "a", "---\ntitle: x\n---\n\nbody\nline", "---\na: 1\n---\n", "pas d'en-tête\n\n"] {
            let body = MarkdownPage.parse(text).body
            let slow = max(text.components(separatedBy: "\n").count - body.components(separatedBy: "\n").count, 0)
            XCTAssertEqual(MarkdownPage.headerLineCount(text, body: body), slow, text)
        }
    }

    func testWindowsLineEndingsStillParse() {
        let page = MarkdownPage.parse("---\r\ntitle: T\r\n---\r\n\r\ntexte")
        XCTAssertEqual(page.frontMatter["title"], "T")
        XCTAssertEqual(page.body, "\ntexte")
    }

    func testFastPathsGiveTheSameResults() {
        XCTAssertEqual(MarkdownPage.tags(in: "aucun tag ici"), [])
        XCTAssertEqual(MarkdownPage.tags(in: "---\ntags: a, b\n---\n"), ["a", "b"])
        XCTAssertEqual(MarkdownPage.usedVariableNames(in: "rien"), [])
        XCTAssertEqual(MarkdownPage.substitute("sans variable", variables: [PageVariable(name: "X", value: "1")]), "sans variable")
        XCTAssertEqual(MarkdownPage.substitute("{{X}}", variables: []), "{{X}}")
        XCTAssertEqual(MarkdownPage.substitute("{{X}}", variables: [PageVariable(name: "X", value: "1")]), "1")
    }

    func testPageAnalysisIsCachedAndCorrect() {
        let cache = PageAnalysisCache()
        let text = "---\ntitle: T\ntags: lab\nvars:\n  IP: 1.2.3.4\n---\n\nssh {{IP}} {{USER}} #réseau"
        let first = cache.analysis(of: text)
        XCTAssertEqual(first.page.frontMatter["title"], "T")
        XCTAssertEqual(first.tags, ["lab", "réseau"])
        XCTAssertEqual(first.undeclaredVariables, ["USER"])
        XCTAssertEqual(first.headerLines, 6)
        XCTAssertEqual(cache.analysis(of: text).tags, first.tags)
        XCTAssertEqual(cache.analysis(of: text + " #autre").tags, ["lab", "réseau", "autre"], "nouveau texte : nouvelle analyse")
    }

    func testEntriesKnowTheirNormalizedPath() {
        let entry = SearchEntry(url: URL(fileURLWithPath: "/w/dossier/../Page.md"), title: "Page", fileName: "Page",
                                path: "Page", body: "")
        XCTAssertEqual(entry.filePath, "/w/Page.md")
    }

    func testNavigationShortcutsAreGroupedAndFree() {
        let settings = ShortcutSettings()
        for action in [ShortcutAction.goBack, .goForward, .previousPage, .nextPage] {
            XCTAssertEqual(action.group, .go)
            XCTAssertEqual(settings.action(using: action.defaultCombo), action)
        }
        XCTAssertEqual(ShortcutAction.goBack.defaultCombo.display, "⌃⌘←")
        XCTAssertEqual(ShortcutAction.nextPage.defaultCombo.display, "⌃⌘↓")
    }
}
