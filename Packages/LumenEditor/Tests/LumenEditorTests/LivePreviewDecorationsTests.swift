//
//  LivePreviewDecorationsTests.swift
//  LumenEditorTests
//
//  P2.2.1 (lumen-nmm.5) SPIKE — verifies the pure active-line reveal logic:
//  given a selection + parsed nodes, which Style-class marker ranges are
//  concealed (raw hidden, content styled) vs revealed (raw markers shown).
//

import AppKit
import XCTest

@testable import LumenEditor

final class LivePreviewDecorationsTests: XCTestCase {
    private func parse(_ text: String) async throws -> [MarkdownSyntaxNode] {
        let parser = try MarkdownTreeSitterParser()
        await parser.parse(text)
        return await parser.nodes(in: NSRange(location: 0, length: (text as NSString).length))
    }

    private func substrings(_ ranges: [NSRange], in text: String) -> [String] {
        let ns = text as NSString
        return ranges.map { ns.substring(with: $0) }
    }

    // MARK: - Marker extraction

    func testMarkerExtractionCoversAllStyleClassMarkers() async throws {
        let text = "# Title\n\nSome **bold** and *italic* and `code` here.\n"
        let nodes = try await parse(text)
        let markers = LivePreviewDecorations.markerRanges(from: nodes, in: text as NSString)
        let strings = substrings(markers, in: text)
        // Heading marker folds the trailing space: "# ".
        XCTAssertTrue(strings.contains("# "), "got \(strings)")
        // Bold = two adjacent `*` delimiters (kept as separate 1-char markers).
        XCTAssertEqual(strings.filter { $0 == "*" }.count, 6, "got \(strings)")
        XCTAssertEqual(strings.filter { $0 == "`" }.count, 2, "got \(strings)")
    }

    // MARK: - Strikethrough & highlight (extended S-class)

    func testStrikethroughDelimitersAreConcealedOnInactiveLine() async throws {
        // Strikethrough `~` delimiters surface as `emphasis_delimiter` nodes,
        // so they conceal by the same rule as bold/italic.
        let text = "a line\n~~struck~~ here\n"
        let nodes = try await parse(text)
        let ns = text as NSString
        // Caret on line one — line two's strikethrough markers stay concealed.
        let (concealed, _) = LivePreviewDecorations.resolve(
            in: ns, selections: [NSRange(location: 0, length: 0)], nodes: nodes)
        XCTAssertEqual(
            concealed.filter { ns.substring(with: $0) == "~" }.count, 4,
            "got \(substrings(concealed, in: text))")
    }

    func testStrikethroughRevealedOnActiveLine() async throws {
        let text = "~~struck~~ here\n"
        let nodes = try await parse(text)
        let ns = text as NSString
        let (concealed, revealed) = LivePreviewDecorations.resolve(
            in: ns, selections: [NSRange(location: 2, length: 0)], nodes: nodes)
        XCTAssertTrue(concealed.isEmpty, "got \(concealed)")
        XCTAssertEqual(revealed.filter { ns.substring(with: $0) == "~" }.count, 4)
    }

    func testHighlightSpansAreScannedAndConcealed() async throws {
        // `==` is NOT in the grammar — exercise the text scanner via resolve.
        let text = "plain\n==marked== text\n"
        let nodes = try await parse(text)
        let ns = text as NSString
        let (concealed, _) = LivePreviewDecorations.resolve(
            in: ns, selections: [NSRange(location: 0, length: 0)], nodes: nodes)
        XCTAssertTrue(
            substrings(concealed, in: text).contains("=="),
            "got \(substrings(concealed, in: text))")
        XCTAssertEqual(
            concealed.filter { ns.substring(with: $0) == "==" }.count, 2)
    }

    func testHighlightSpanContentAndDelimiters() {
        let text = "==marked== and ==two== end" as NSString
        let spans = LivePreviewDecorations.highlightSpans(in: text)
        XCTAssertEqual(spans.count, 2)
        XCTAssertEqual(text.substring(with: spans[0].open), "==")
        XCTAssertEqual(text.substring(with: spans[0].content), "marked")
        XCTAssertEqual(text.substring(with: spans[1].content), "two")
    }

    func testHighlightIgnoresUnbalancedEmptyEscapedAndMultiline() {
        // Unbalanced (typing): single opener, no closer.
        XCTAssertTrue(
            LivePreviewDecorations.highlightSpans(in: "==typing now" as NSString).isEmpty)
        // Empty / blank content.
        XCTAssertTrue(LivePreviewDecorations.highlightSpans(in: "====" as NSString).isEmpty)
        XCTAssertTrue(
            LivePreviewDecorations.highlightSpans(in: "==   ==" as NSString).isEmpty)
        // Escaped opening `=` is literal.
        XCTAssertTrue(
            LivePreviewDecorations.highlightSpans(in: "\\==x==" as NSString).isEmpty)
        // Span may not cross a newline.
        XCTAssertTrue(
            LivePreviewDecorations.highlightSpans(in: "==a\nb==" as NSString).isEmpty)
    }

    func testHighlightRevealedOnActiveLine() async throws {
        let text = "==marked== text\n"
        let nodes = try await parse(text)
        let ns = text as NSString
        let (concealed, revealed) = LivePreviewDecorations.resolve(
            in: ns, selections: [NSRange(location: 3, length: 0)], nodes: nodes)
        XCTAssertTrue(concealed.isEmpty)
        XCTAssertEqual(revealed.filter { ns.substring(with: $0) == "==" }.count, 2)
    }

    // MARK: - Caret reveal (per-logical-line)

    func testCaretOnLineRevealsThatLinesMarkersOnly() async throws {
        let text = "**bold** line one\n*italic* line two\n"
        let nodes = try await parse(text)
        let ns = text as NSString
        // Caret on line one (offset 2, inside "bold").
        let caret = NSRange(location: 2, length: 0)
        let (concealed, revealed) = LivePreviewDecorations.resolve(
            in: ns, selections: [caret], nodes: nodes)

        // Line one's `**` markers are revealed; line two's `*` markers concealed.
        XCTAssertEqual(Set(substrings(revealed, in: text)), ["*"])
        XCTAssertEqual(Set(substrings(concealed, in: text)), ["*"])
        // Line one has 4 `*` revealed; line two has 2 `*` concealed.
        XCTAssertEqual(revealed.count, 4)
        XCTAssertEqual(concealed.count, 2)
        // All revealed markers sit on line one; all concealed on line two.
        let lineOne = ns.lineRange(for: NSRange(location: 0, length: 0))
        for r in revealed { XCTAssertTrue(NSLocationInRange(r.location, lineOne)) }
        for r in concealed { XCTAssertFalse(NSLocationInRange(r.location, lineOne)) }
    }

    func testCaretAnywhereOnLineRevealsAllInlineMarkersOnIt() async throws {
        // Two emphasis spans on the same line; caret near the end still reveals
        // BOTH (line-wide reveal, not per-element).
        let text = "**a** mid *b* end\n"
        let nodes = try await parse(text)
        let ns = text as NSString
        let caret = NSRange(location: ns.length - 1, length: 0)  // end of line
        let (concealed, revealed) = LivePreviewDecorations.resolve(
            in: ns, selections: [caret], nodes: nodes)
        XCTAssertTrue(concealed.isEmpty, "nothing should be concealed; got \(concealed)")
        XCTAssertEqual(revealed.count, 6, "all `*` markers revealed; got \(revealed.count)")
    }

    // MARK: - Inactive line conceals

    func testInactiveLinesAreConcealed() async throws {
        let text = "# Heading\n\n**bold** body\n"
        let nodes = try await parse(text)
        let ns = text as NSString
        // Caret in the blank line 2 (offset 10) — neither heading nor body line.
        let caret = NSRange(location: 10, length: 0)
        let (concealed, revealed) = LivePreviewDecorations.resolve(
            in: ns, selections: [caret], nodes: nodes)
        XCTAssertTrue(revealed.isEmpty, "nothing on the blank line; got \(revealed)")
        // Heading "# " + two `**` = 1 + 4 markers concealed.
        XCTAssertEqual(concealed.count, 5, "got \(substrings(concealed, in: text))")
        XCTAssertTrue(substrings(concealed, in: text).contains("# "))
    }

    // MARK: - Multi-line selection reveals every touched line

    func testMultiLineSelectionRevealsEveryCoveredLine() async throws {
        let text = "**a**\n*b*\n`c`\n"
        let nodes = try await parse(text)
        let ns = text as NSString
        // Select from line 1 through into line 3.
        let selection = NSRange(location: 0, length: ns.length - 1)
        let (concealed, revealed) = LivePreviewDecorations.resolve(
            in: ns, selections: [selection], nodes: nodes)
        XCTAssertTrue(concealed.isEmpty, "multi-line selection reveals all; got \(concealed)")
        // `**a**` = 4 `*` delimiters, `*b*` = 2, `` `c` `` = 2 ⇒ 8 markers.
        XCTAssertEqual(revealed.count, 8)
    }

    // MARK: - Buffer is never consulted/mutated; ranges stay in bounds

    func testResolvedRangesAreWithinDocumentBounds() async throws {
        let text = "# H\n**x** `y` _z_\n"
        let nodes = try await parse(text)
        let ns = text as NSString
        let (concealed, revealed) = LivePreviewDecorations.resolve(
            in: ns, selections: [NSRange(location: 0, length: 0)], nodes: nodes)
        for r in concealed + revealed {
            XCTAssertGreaterThanOrEqual(r.location, 0)
            XCTAssertLessThanOrEqual(NSMaxRange(r), ns.length)
        }
    }
}
