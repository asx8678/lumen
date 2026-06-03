//
//  MarkdownDocumentParserTests.swift
//  LumenCoreTests
//
//  Verifies the swift-markdown full-document AST lowering (P2.0.3): the
//  ``MarkdownBlock``/``MarkdownInline`` intermediate is correct for the GFM
//  constructs the reading view (P2.1.1) needs, and that YAML frontmatter is
//  stripped before parsing the body.
//

import XCTest

@testable import LumenCore

final class MarkdownDocumentParserTests: XCTestCase {

    // MARK: - Helpers

    private func blocks(_ text: String) -> [MarkdownBlock] {
        MarkdownDocumentParser.parseBlocks(text)
    }

    // MARK: - Headings & paragraphs

    func testHeadingsAtAllLevels() {
        let result = blocks("# H1\n\n###### H6")
        XCTAssertEqual(
            result,
            [
                .heading(level: 1, [.text("H1")]),
                .heading(level: 6, [.text("H6")]),
            ])
    }

    func testParagraph() {
        XCTAssertEqual(blocks("Just a paragraph."), [.paragraph([.text("Just a paragraph.")])])
    }

    // MARK: - Emphasis / strong / strikethrough

    func testEmphasisAndStrong() {
        let result = blocks("*em* and **strong**")
        XCTAssertEqual(
            result,
            [
                .paragraph([
                    .emphasis([.text("em")]),
                    .text(" and "),
                    .strong([.text("strong")]),
                ])
            ])
    }

    func testStrikethrough() {
        XCTAssertEqual(
            blocks("~~gone~~"),
            [.paragraph([.strikethrough([.text("gone")])])])
    }

    // MARK: - Code

    func testInlineCode() {
        XCTAssertEqual(
            blocks("call `foo()` now"),
            [.paragraph([.text("call "), .inlineCode("foo()"), .text(" now")])])
    }

    func testFencedCodeBlockWithLanguage() {
        let result = blocks("```swift\nlet x = 1\n```")
        XCTAssertEqual(result, [.codeBlock(language: "swift", code: "let x = 1\n")])
    }

    func testFencedCodeBlockWithoutLanguage() {
        let result = blocks("```\nplain\n```")
        XCTAssertEqual(result, [.codeBlock(language: nil, code: "plain\n")])
    }

    // MARK: - Links & images

    func testLink() {
        XCTAssertEqual(
            blocks("[Lumen](https://example.com)"),
            [.paragraph([.link(destination: "https://example.com", [.text("Lumen")])])])
    }

    func testImage() {
        XCTAssertEqual(
            blocks("![alt text](pic.png)"),
            [.paragraph([.image(source: "pic.png", alt: "alt text")])])
    }

    // MARK: - Lists

    func testUnorderedList() {
        let result = blocks("- one\n- two")
        XCTAssertEqual(
            result,
            [
                .unorderedList([
                    MarkdownListItem(children: [.paragraph([.text("one")])]),
                    MarkdownListItem(children: [.paragraph([.text("two")])]),
                ])
            ])
    }

    func testOrderedListStartIndex() {
        let result = blocks("3. three\n4. four")
        XCTAssertEqual(
            result,
            [
                .orderedList(
                    start: 3,
                    items: [
                        MarkdownListItem(children: [.paragraph([.text("three")])]),
                        MarkdownListItem(children: [.paragraph([.text("four")])]),
                    ])
            ])
    }

    func testTaskList() {
        let result = blocks("- [ ] todo\n- [x] done")
        XCTAssertEqual(
            result,
            [
                .unorderedList([
                    MarkdownListItem(
                        checkbox: .unchecked, children: [.paragraph([.text("todo")])]),
                    MarkdownListItem(
                        checkbox: .checked, children: [.paragraph([.text("done")])]),
                ])
            ])
    }

    // MARK: - Block quotes / thematic breaks

    func testBlockQuote() {
        XCTAssertEqual(
            blocks("> quoted"),
            [.blockQuote([.paragraph([.text("quoted")])])])
    }

    func testThematicBreak() {
        let result = blocks("above\n\n---\n\nbelow")
        XCTAssertEqual(
            result,
            [
                .paragraph([.text("above")]),
                .thematicBreak,
                .paragraph([.text("below")]),
            ])
    }

    // MARK: - Tables

    func testTableWithAlignments() {
        let source = """
            | Left | Center | Right |
            | :--- | :----: | ----: |
            | a    | b      | c     |
            """
        let result = blocks(source)
        XCTAssertEqual(
            result,
            [
                .table(
                    MarkdownTable(
                        columnAlignments: [.left, .center, .right],
                        header: [[.text("Left")], [.text("Center")], [.text("Right")]],
                        rows: [[[.text("a")], [.text("b")], [.text("c")]]]))
            ])
    }

    // MARK: - Frontmatter stripping

    func testFrontmatterIsStrippedBeforeParsing() {
        let source = """
            ---
            title: Demo
            tags: [a, b]
            ---
            # Real Heading

            Body text.
            """
        let result = blocks(source)
        XCTAssertEqual(
            result,
            [
                .heading(level: 1, [.text("Real Heading")]),
                .paragraph([.text("Body text.")]),
            ])
        // The `---` fences must not appear as thematic breaks in the tree.
        XCTAssertFalse(result.contains(.thematicBreak))
    }

    // MARK: - Document API

    func testParseDocumentReturnsBodyOnly() {
        let document = MarkdownDocumentParser.parseDocument("---\nk: v\n---\nHello")
        // One paragraph child; no frontmatter leakage.
        XCTAssertEqual(document.childCount, 1)
    }
}
