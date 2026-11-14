import XCTest
@testable import CairnCore

final class TagRewriterTests: XCTestCase {
    private let page = "---\ntitle: T\ntags: iam, reseau\n---\n\nVoir #IAM et `#iam`.\n"

    func testRenameInHeaderAndText() {
        XCTAssertEqual(
            TagRewriter.rewrite("iam", to: "identites", in: page),
            "---\ntitle: T\ntags: identites, reseau\n---\n\nVoir #identites et `#iam`.\n"
        )
    }

    func testMergeRemovesDuplicate() {
        XCTAssertEqual(
            TagRewriter.rewrite("iam", to: "reseau", in: page),
            "---\ntitle: T\ntags: reseau\n---\n\nVoir #reseau et `#iam`.\n"
        )
    }

    func testRemoveKeepsTheWord() {
        XCTAssertEqual(
            TagRewriter.rewrite("iam", to: nil, in: page),
            "---\ntitle: T\ntags: reseau\n---\n\nVoir IAM et `#iam`.\n"
        )
    }

    func testNameWithSpacesGoesToHeader() {
        XCTAssertEqual(
            TagRewriter.rewrite("iam", to: "gestion des accès", in: "Note #iam ici"),
            "---\ntags: gestion des accès\n---\n\nNote iam ici"
        )
    }

    func testOtherTagsAreUntouched() {
        XCTAssertEqual(TagRewriter.rewrite("cloud", to: "nuage", in: page), page)
    }
}
