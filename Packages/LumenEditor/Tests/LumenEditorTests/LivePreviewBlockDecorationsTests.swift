//
//  LivePreviewBlockDecorationsTests.swift
//  LumenEditorTests
//
//  P2.2.1c (lumen-nmm.19) — pure-logic tests for block-level live-preview
//  decorations: blockquote region/depth/marker extraction, list bullet
//  substitution + nesting depth, and fenced/indented code-block region
//  detection. Mirrors the headless style of LivePreviewDecorationsTests.
//

import AppKit
import XCTest

@testable import LumenEditor

final class LivePreviewBlockDecorationsTests: XCTestCase {
    private func parse(_ text: String) async throws -> [MarkdownSyntaxNode] {
        let parser = try MarkdownTreeSitterParser()
        await parser.parse(text)
        return await parser.nodes(in: NSRange(location: 0, length: (text as NSString).length))
    }

    private func substrings(_ ranges: [NSRange], in text: String) -> [String] {
        let ns = text as NSString
        return ranges.map { ns.substring(with: $0) }
    }

    // MARK: - Blockquote

    func testBlockquoteRegionAndDepth() async throws {
        let text = "> quote line one\n> quote line two\n> > nested quote\n"
        let nodes = try await parse(text)
        let regions = LivePreviewBlockDecorations.blockquoteRegions(from: nodes)
        XCTAssertFalse(regions.isEmpty)
        // The outer region covers the whole quote at depth 1.
        XCTAssertEqual(regions.first?.depth, 1)
        // A nested `> >` region reports depth 2.
        XCTAssertTrue(regions.contains { $0.depth == 2 }, "got \(regions)")
        // Depth probe: offset on the nested line is 2, on a plain line is 1.
        let ns = text as NSString
        let nestedLoc = ns.range(of: "nested").location
        XCTAssertEqual(
            LivePreviewBlockDecorations.blockquoteDepth(at: nestedLoc, regions: regions), 2)
        let plainLoc = ns.range(of: "line one").location
        XCTAssertEqual(
            LivePreviewBlockDecorations.blockquoteDepth(at: plainLoc, regions: regions), 1)
    }

    func testBlockquoteMarkersCoverEveryLine() async throws {
        let text = "> line one\n> line two\n"
        let nodes = try await parse(text)
        let markers = LivePreviewBlockDecorations.blockquoteMarkerRanges(
            from: nodes, in: text as NSString)
        // One `> ` marker per quote line (first via block_quote_marker,
        // subsequent via the `>`-bearing block_continuation).
        let strings = substrings(markers, in: text)
        XCTAssertEqual(strings.filter { $0.contains(">") }.count, 2, "got \(strings)")
    }

    func testBlockquoteMarkerRevealOnActiveLineKeepsRegion() async throws {
        let text = "> line one\n> line two\n"
        let nodes = try await parse(text)
        let ns = text as NSString
        let markers = LivePreviewBlockDecorations.blockquoteMarkerRanges(
            from: nodes, in: ns)
        // Caret on line one reveals only its marker; line two stays concealed.
        let (concealed, revealed) = LivePreviewDecorations.partition(
            markers: markers, in: ns,
            selections: [NSRange(location: 0, length: 0)])
        XCTAssertEqual(concealed.count, 1)
        XCTAssertEqual(revealed.count, 1)
        // The region itself is independent of reveal — the bar persists.
        let regions = LivePreviewBlockDecorations.blockquoteRegions(from: nodes)
        XCTAssertEqual(
            LivePreviewBlockDecorations.blockquoteDepth(at: 0, regions: regions), 1)
    }

    func testFrontmatterIsNotAQuote() async throws {
        // First-line `---…---` is YAML frontmatter, NOT a blockquote/HR.
        let text = "---\ntitle: hi\n---\n\n> real quote\n"
        let nodes = try await parse(text)
        let regions = LivePreviewBlockDecorations.blockquoteRegions(from: nodes)
        // Only the genuine `>` quote yields a region.
        XCTAssertEqual(regions.count, 1)
        let ns = text as NSString
        let quoteLoc = ns.range(of: "real").location
        XCTAssertEqual(
            LivePreviewBlockDecorations.blockquoteDepth(at: quoteLoc, regions: regions), 1)
    }

    // MARK: - Lists

    func testBulletSubstitutionsAndDepth() async throws {
        let text = "- a\n- b\n  - nested\n* star\n+ plus\n"
        let nodes = try await parse(text)
        let subs = LivePreviewBlockDecorations.bulletSubstitutions(from: nodes)
        // Four top-level + one nested = five unordered markers.
        XCTAssertEqual(subs.count, 5, "got \(subs)")
        XCTAssertTrue(subs.allSatisfy { $0.replacement == LivePreviewBlockDecorations.bulletGlyph })
        // The indented `- nested` is depth 2; the others are depth 1.
        XCTAssertTrue(subs.contains { $0.depth == 2 }, "got \(subs.map(\.depth))")
        XCTAssertEqual(subs.filter { $0.depth == 1 }.count, 4, "got \(subs.map(\.depth))")
    }

    func testOrderedMarkersAreNotSubstituted() async throws {
        let text = "1. one\n2. two\n"
        let nodes = try await parse(text)
        let subs = LivePreviewBlockDecorations.bulletSubstitutions(from: nodes)
        XCTAssertTrue(subs.isEmpty, "ordered markers must stay as-is, got \(subs)")
        // But ordered items still report a list depth (for indentation).
        let ns = text as NSString
        let loc = ns.range(of: "one").location
        XCTAssertEqual(LivePreviewBlockDecorations.listDepth(at: loc, from: nodes), 1)
    }

    // MARK: - Code blocks

    func testFencedCodeRegionDetected() async throws {
        let text = "before\n\n```swift\nlet x = 1\n```\n\nafter\n"
        let nodes = try await parse(text)
        let regions = LivePreviewBlockDecorations.codeBlockRegions(from: nodes)
        XCTAssertEqual(regions.count, 1)
        XCTAssertTrue(regions.first?.isFenced == true)
        // The fenced region covers the opening fence + content + closing fence.
        let ns = text as NSString
        let region = try XCTUnwrap(regions.first)
        let covered = ns.substring(with: region.range)
        XCTAssertTrue(covered.contains("```swift"), "got \(covered)")
        XCTAssertTrue(covered.contains("let x = 1"), "got \(covered)")
    }

    func testIndentedCodeRegionDetected() async throws {
        let text = "para\n\n    indented code\n    more code\n\nafter\n"
        let nodes = try await parse(text)
        let regions = LivePreviewBlockDecorations.codeBlockRegions(from: nodes)
        XCTAssertTrue(regions.contains { $0.isFenced == false }, "got \(regions)")
    }

    func testSetextUnderlineDoesNotBecomeCodeOrQuote() async throws {
        // `===` under a text line is a setext heading underline, not HR/code.
        let text = "Title\n===\n\nbody\n"
        let nodes = try await parse(text)
        XCTAssertTrue(LivePreviewBlockDecorations.codeBlockRegions(from: nodes).isEmpty)
        XCTAssertTrue(LivePreviewBlockDecorations.blockquoteRegions(from: nodes).isEmpty)
    }
}
