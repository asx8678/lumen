//
//  MarkdownTreeSitterHighlighterTests.swift
//  LumenEditorTests
//
//  P2.0.2: proves the tree-sitter-driven highlighter maps parse nodes onto the
//  correct theme attributes for representative Markdown — including nested
//  cases the old regex highlighter got wrong (bold inside a list item,
//  emphasis inside a heading).
//

import AppKit
import LumenBenchmark
import XCTest

@testable import LumenEditor

@MainActor
final class MarkdownTreeSitterHighlighterTests: XCTestCase {
    private let highlighter = MarkdownTreeSitterHighlighter()

    private func makeParser() throws -> MarkdownTreeSitterParser {
        try MarkdownTreeSitterParser()
    }

    private func fullRange(_ text: String) -> NSRange {
        NSRange(location: 0, length: (text as NSString).length)
    }

    /// Parses `text`, queries its nodes, and maps them to styled spans.
    private func styledRanges(
        for text: String,
        theme: MarkdownHighlightTheme = .default
    ) async throws -> [MarkdownTreeSitterHighlighter.StyledRange] {
        let parser = try makeParser()
        await parser.parse(text)
        let nodes = await parser.nodes(in: fullRange(text))
        return highlighter.styledRanges(for: nodes, theme: theme)
    }

    /// The substrings of `text` covered by spans whose attributes match.
    private func substrings(
        _ spans: [MarkdownTreeSitterHighlighter.StyledRange],
        in text: String,
        where predicate: ([NSAttributedString.Key: Any]) -> Bool
    ) -> [String] {
        let ns = text as NSString
        return spans.filter { predicate($0.attributes) }
            .map { ns.substring(with: $0.range) }
    }

    private func hasColor(
        _ attributes: [NSAttributedString.Key: Any],
        _ color: NSColor
    ) -> Bool {
        (attributes[.foregroundColor] as? NSColor) == color
    }

    private func isBold(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        guard let font = attributes[.font] as? NSFont else { return false }
        return font.fontDescriptor.symbolicTraits.contains(.bold)
    }

    private func isItalic(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        guard let font = attributes[.font] as? NSFont else { return false }
        return font.fontDescriptor.symbolicTraits.contains(.italic)
    }

    // MARK: - Core token coverage

    func testHeadingIsStyled() async throws {
        let text = "# Heading\n"
        let theme = MarkdownHighlightTheme.default
        let spans = try await styledRanges(for: text, theme: theme)
        let headings = substrings(spans, in: text) { hasColor($0, theme.headingColor) }
        XCTAssertTrue(
            headings.contains { $0.hasPrefix("# Heading") },
            "expected heading span; got \(headings)")
    }

    func testBoldItalicCodeLinkAreStyled() async throws {
        let text = "Some **bold** and *italic* and `code` and [label](https://x.com).\n"
        let theme = MarkdownHighlightTheme.default
        let spans = try await styledRanges(for: text, theme: theme)

        XCTAssertTrue(
            substrings(spans, in: text) { isBold($0) }.contains("**bold**"),
            "bold not styled")
        XCTAssertTrue(
            substrings(spans, in: text) { isItalic($0) }.contains("*italic*"),
            "italic not styled")
        XCTAssertTrue(
            substrings(spans, in: text) { hasColor($0, theme.codeColor) }
                .contains("`code`"),
            "inline code not styled")
        XCTAssertTrue(
            substrings(spans, in: text) { hasColor($0, theme.linkTextColor) }
                .contains("label"),
            "link text not styled")
        XCTAssertTrue(
            substrings(spans, in: text) { hasColor($0, theme.linkURLColor) }
                .contains("https://x.com"),
            "link URL not styled")
    }

    func testListMarkerAndBlockquoteAreStyled() async throws {
        let text = "- item one\n- item two\n\n> quoted line\n"
        let theme = MarkdownHighlightTheme.default
        let spans = try await styledRanges(for: text, theme: theme)
        XCTAssertFalse(
            substrings(spans, in: text) { hasColor($0, theme.listMarkerColor) }.isEmpty,
            "list marker not styled")
        XCTAssertFalse(
            substrings(spans, in: text) { hasColor($0, theme.quoteColor) }.isEmpty,
            "blockquote not styled")
    }

    func testFencedCodeBlockIsStyled() async throws {
        let text = "```swift\nlet x = 1\nlet y = 2\n```\n"
        let theme = MarkdownHighlightTheme.default
        let spans = try await styledRanges(for: text, theme: theme)
        // The multi-line content is colored as code (something the line-based
        // regex highlighter could only approximate at the viewport edge).
        let codeSpans = substrings(spans, in: text) { hasColor($0, theme.codeColor) }
        XCTAssertTrue(
            codeSpans.contains { $0.contains("let x = 1") && $0.contains("let y = 2") },
            "fenced code block content not styled as code; got \(codeSpans)")
    }

    // MARK: - Nested cases the regex highlighter got wrong

    /// Bold INSIDE a list item: the old per-line regex matched the list marker
    /// but did not detect emphasis nested in the item text reliably.
    func testBoldInsideListItemIsStyled() async throws {
        let text = "- a list item with **bold** inside\n"
        let theme = MarkdownHighlightTheme.default
        let spans = try await styledRanges(for: text, theme: theme)
        XCTAssertTrue(
            substrings(spans, in: text) { isBold($0) && hasColor($0, theme.emphasisColor) }
                .contains("**bold**"),
            "bold nested in a list item was not styled")
        // The list marker is still styled distinctly.
        XCTAssertFalse(
            substrings(spans, in: text) { hasColor($0, theme.listMarkerColor) }.isEmpty,
            "list marker missing")
    }

    /// Emphasis INSIDE a heading: tree-sitter parses the heading's inline
    /// content, so the emphasized run is detected — the regex path colored the
    /// whole heading line uniformly and missed the nested emphasis.
    func testEmphasisInsideHeadingIsStyled() async throws {
        let text = "# Title with *emphasis* here\n"
        let theme = MarkdownHighlightTheme.default
        let spans = try await styledRanges(for: text, theme: theme)
        XCTAssertTrue(
            substrings(spans, in: text) { isItalic($0) }.contains("*emphasis*"),
            "emphasis nested in a heading was not styled")
    }

    // MARK: - Empty input

    func testNoNodesProducesNoSpans() {
        let spans = highlighter.styledRanges(for: [], theme: .default)
        XCTAssertTrue(spans.isEmpty)
    }

    // MARK: - Performance (mapping a viewport's worth of nodes is cheap)

    func testMappingNodesIsCheap() async throws {
        let text = SyntheticData.markdownDocument(lineCount: 2_000)
        let parser = try makeParser()
        await parser.parse(text)
        let ns = text as NSString
        let viewport = ns.paragraphRange(
            for: NSRange(location: ns.length / 2, length: min(2_000, ns.length / 4)))
        let nodes = await parser.nodes(in: viewport)
        let theme = MarkdownHighlightTheme.default
        measure {
            _ = highlighter.styledRanges(for: nodes, theme: theme)
        }
    }
}
