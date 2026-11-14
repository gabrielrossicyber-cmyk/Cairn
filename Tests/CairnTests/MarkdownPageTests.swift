import XCTest
@testable import CairnCore

final class MarkdownPageTests: XCTestCase {

    func testParseSeparatesHeaderVariablesAndBody() {
        let text = "---\nid: abc\ntitle: \"Lab: Nmap\"\nvars:\n  IP_CIBLE: 10.0.0.5\n---\n\n# Lab\n"
        let page = MarkdownPage.parse(text)
        XCTAssertEqual(page.frontMatter["id"], "abc")
        XCTAssertEqual(page.frontMatter["title"], "Lab: Nmap")
        XCTAssertEqual(page.variables, [PageVariable(name: "IP_CIBLE", value: "10.0.0.5")])
        XCTAssertEqual(page.body, "\n# Lab\n")
    }

    func testParseWithoutHeaderKeepsWholeText() {
        let page = MarkdownPage.parse("# Titre\ntexte")
        XCTAssertTrue(page.frontMatter.isEmpty)
        XCTAssertEqual(page.body, "# Titre\ntexte")
    }

    func testTagsFromHeaderAndText() {
        let text = """
        ---
        title: T
        tags: iso27001, Analyse des besoins
        ---

        # Titre
        Texte #IAM et `#pascode` et https://x.ch/page#ancre
        ```
        #danscode
        ```
        #Réseau #reseau
        """
        XCTAssertEqual(MarkdownPage.tags(in: text), ["iso27001", "Analyse des besoins", "IAM", "Réseau"])
    }

    func testTagsAsYamlList() {
        let text = "---\ntags:\n  - iam\n  - cloud\ntitle: T\n---\ntexte"
        XCTAssertEqual(MarkdownPage.tags(in: text), ["iam", "cloud"])
    }

    func testSubstituteReplacesOnlyKnownVariables() {
        let result = MarkdownPage.substitute(
            "ping {{IP}} {{ INCONNU }} {{secret:X}}",
            variables: [PageVariable(name: "IP", value: "1.2.3.4")]
        )
        XCTAssertEqual(result, "ping 1.2.3.4 {{ INCONNU }} {{secret:X}}")
    }

    func testSecretsAreNotVariables() {
        let text = "a {{secret:A}} b {{ secret:B-2 }} {{secret:A}} {{IP}}"
        XCTAssertEqual(MarkdownPage.usedVariableNames(in: text), ["IP"])
        XCTAssertEqual(SecretStore.usedNames(in: text), ["A", "B-2"])
    }

    func testTogglingTaskSkipsCodeBlocks() {
        let text = "- [ ] a\n- [x] b\n```\n- [ ] code\n```\n- [ ] c"
        XCTAssertEqual(MarkdownPage.togglingTask(at: 2, in: text), "- [ ] a\n- [x] b\n```\n- [ ] code\n```\n- [x] c")
        XCTAssertEqual(MarkdownPage.togglingTask(at: 1, in: text), "- [ ] a\n- [ ] b\n```\n- [ ] code\n```\n- [ ] c")
        XCTAssertEqual(MarkdownPage.togglingTask(at: 9, in: text), text)
    }

    func testHeadingsIgnoreHeaderCodeAndTags() {
        let text = "---\ntitle: x\n---\n# A\n```\n# pas un titre\n```\n## B ##\n#tag"
        let headings = MarkdownPage.headings(in: text)
        XCTAssertEqual(headings.map(\.title), ["A", "B"])
        XCTAssertEqual(headings.map(\.level), [1, 2])
        XCTAssertEqual(headings.first?.location, 17)
    }

    func testYamlValueQuotesSpecialCharacters() {
        XCTAssertEqual(MarkdownPage.yamlValue("Simple"), "Simple")
        XCTAssertEqual(MarkdownPage.yamlValue("a: b"), "\"a: b\"")
    }

    func testSettingVariableCreatesHeader() {
        let text = MarkdownPage.settingVariable("X", to: "1", in: "texte")
        XCTAssertEqual(text, "---\nvars:\n  X: 1\n---\n\ntexte")
        XCTAssertEqual(MarkdownPage.parse(text).variables, [PageVariable(name: "X", value: "1")])
    }
}
