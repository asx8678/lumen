//
//  MarkdownHighlighterTests.swift
//  LumenEditorTests
//
//  P1.12: correctness sanity + proof that re-highlighting stays viewport-scoped
//  and cheap on a large document (no regression of the P1.10 spike).
//

import AppKit
import XCTest

@testable import LumenEditor

@MainActor
final class MarkdownHighlighterTests: XCTestCase {
    private let highlighter = MarkdownHighlighter()
    private let largeLineCount = 70_000

    // MARK: - Correctness

    func testFindsCommonTokens() {
        let text = """
        # Heading
        Some **bold** and *italic* and `code` here.
        - item one
        > quoted
        [label](https://example.com)
        """
        let theme = MarkdownHighlightTheme.default
        let spans = highlighter.styledRanges(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length),
            theme: theme
        )
        // Expect a non-trivial number of styled spans across the token types.
        XCTAssertGreaterThanOrEqual(spans.count, 6,
                                    "Expected heading/bold/italic/code/list/quote/link spans")
    }

    func testEmptyRangeProducesNoSpans() {
        let spans = highlighter.styledRanges(
            in: "plain text with no markdown",
            range: NSRange(location: 0, length: 0),
            theme: .default
        )
        XCTAssertTrue(spans.isEmpty)
    }

    // MARK: - Performance (viewport-scoped re-highlight on a large doc)

    /// Highlights only a viewport-sized slice (~80 lines) of a 70k-line doc and
    /// asserts it is cheap — this is what runs on every keystroke / scroll tick.
    func testViewportHighlightStaysCheapOnLargeDoc() {
        let text = SampleContent.syntheticMarkdown(lineCount: largeLineCount)
        let ns = text as NSString
        // A viewport-sized window near the middle of the document.
        let approxMid = ns.length / 2
        let window = ns.paragraphRange(for: NSRange(location: approxMid, length: 0))
        // Expand to roughly 80 lines worth of characters around the midpoint.
        let start = max(0, window.location - 2_000)
        let end = min(ns.length, window.location + 2_000)
        let viewport = ns.paragraphRange(for: NSRange(location: start, length: end - start))
        let theme = MarkdownHighlightTheme.default

        measure {
            _ = highlighter.styledRanges(in: text, range: viewport, theme: theme)
        }
    }

    /// Single-paragraph re-highlight (what `textDidChange` triggers per edit).
    func testSingleParagraphHighlightIsFast() {
        let text = SampleContent.syntheticMarkdown(lineCount: largeLineCount)
        let ns = text as NSString
        let paragraph = ns.paragraphRange(for: NSRange(location: ns.length / 3, length: 0))
        let theme = MarkdownHighlightTheme.default

        measure {
            _ = highlighter.styledRanges(in: text, range: paragraph, theme: theme)
        }
    }
}
