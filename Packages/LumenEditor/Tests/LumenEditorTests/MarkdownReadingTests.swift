//
//  MarkdownReadingTests.swift
//  LumenEditorTests
//
//  P2.1.1: the reading-view mapping. Verifies that the LumenCore renderable
//  block/inline model lowers into the expected rendered structure
//  (MarkdownReadingOutline) and that inline runs carry the right styling
//  intents and link attributes (MarkdownInlineRenderer).
//

import Foundation
import XCTest

@testable import LumenCore
@testable import LumenEditor

final class MarkdownReadingTests: XCTestCase {

    // MARK: - Structural mapping

    func testHeadingsMapToLeveledTags() {
        let blocks = MarkdownDocumentParser.parseBlocks("# One\n\n## Two\n\n### Three")
        XCTAssertEqual(
            MarkdownReadingOutline.describe(blocks),
            ["h1", "h2", "h3"])
    }

    func testParagraphWithInlineMixAndLink() {
        let blocks = MarkdownDocumentParser.parseBlocks(
            "A **bold** and *italic* and `code` with a [link](https://example.com).")
        XCTAssertEqual(MarkdownReadingOutline.describe(blocks), ["p", "link"])
    }

    func testCodeBlockKeepsLanguage() {
        let source = """
            ```swift
            let x = 1
            ```
            """
        let blocks = MarkdownDocumentParser.parseBlocks(source)
        XCTAssertEqual(MarkdownReadingOutline.describe(blocks), ["code(swift)"])
    }

    func testTaskListCheckboxesAreRecognized() {
        let source = """
            - [ ] todo
            - [x] done
            - plain
            """
        let blocks = MarkdownDocumentParser.parseBlocks(source)
        XCTAssertEqual(
            MarkdownReadingOutline.describe(blocks),
            ["ul", "task[unchecked]", "p", "task[checked]", "p", "li", "p"])
    }

    func testTableMapsToDimensions() {
        let source = """
            | A | B |
            | - | - |
            | 1 | 2 |
            | 3 | 4 |
            """
        let blocks = MarkdownDocumentParser.parseBlocks(source)
        XCTAssertEqual(MarkdownReadingOutline.describe(blocks), ["table(2x2)"])
    }

    func testStandaloneImageParagraphMapsToImage() {
        let blocks = MarkdownDocumentParser.parseBlocks("![alt](pic.png)")
        XCTAssertEqual(MarkdownReadingOutline.describe(blocks), ["image(pic.png)"])
    }

    // MARK: - Inline styling

    func testInlineRendererAppliesIntentsAndLink() {
        let inlines: [MarkdownInline] = [
            .text("plain "),
            .strong([.text("bold")]),
            .text(" "),
            .emphasis([.text("italic")]),
            .text(" "),
            .inlineCode("code"),
            .text(" "),
            .link(destination: "https://example.com", [.text("link")]),
        ]
        let attributed = MarkdownInlineRenderer.attributedString(for: inlines)

        var sawStrong = false
        var sawEmphasis = false
        var sawCode = false
        var linkURL: URL?
        for run in attributed.runs {
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.stronglyEmphasized) { sawStrong = true }
                if intent.contains(.emphasized) { sawEmphasis = true }
                if intent.contains(.code) { sawCode = true }
            }
            if let link = run.link { linkURL = link }
        }
        XCTAssertTrue(sawStrong, "strong run should be stronglyEmphasized")
        XCTAssertTrue(sawEmphasis, "emphasis run should be emphasized")
        XCTAssertTrue(sawCode, "inline code run should carry the code intent")
        XCTAssertEqual(linkURL, URL(string: "https://example.com"))
        XCTAssertEqual(
            String(attributed.characters), "plain bold italic code link")
    }

    func testPlainTextStripsMarkers() {
        let inlines: [MarkdownInline] = [
            .text("a "),
            .strong([.text("b")]),
            .link(destination: "x", [.text(" c")]),
        ]
        XCTAssertEqual(MarkdownInlineRenderer.plainText(for: inlines), "a b c")
    }
}
