//
//  MarkdownTreeSitterParserTests.swift
//  LumenEditorTests
//
//  P2.0.1: proves the tree-sitter backbone yields the expected node types and
//  ranges for representative Markdown, reparses correctly after an incremental
//  edit, and that incremental reparse stays well under the frame budget.
//

import Foundation
import XCTest

@testable import LumenEditor

final class MarkdownTreeSitterParserTests: XCTestCase {
    private func makeParser() throws -> MarkdownTreeSitterParser {
        try MarkdownTreeSitterParser()
    }

    private func types(_ nodes: [MarkdownSyntaxNode]) -> Set<String> {
        Set(nodes.map(\.type))
    }

    private func fullRange(_ text: String) -> NSRange {
        NSRange(location: 0, length: (text as NSString).length)
    }

    // MARK: - Block + inline node types

    func testHeadingProducesAtxHeadingNode() async throws {
        let parser = try makeParser()
        let text = "# Title\n"
        await parser.parse(text)
        let nodes = await parser.nodes(in: fullRange(text))
        XCTAssertTrue(
            types(nodes).contains("atx_heading"), "expected atx_heading; got \(types(nodes))")
    }

    func testEmphasisAndStrongAreDetected() async throws {
        let parser = try makeParser()
        let text = "Some **bold** and *italic* text.\n"
        await parser.parse(text)
        let found = types(await parser.nodes(in: fullRange(text)))
        XCTAssertTrue(found.contains("strong_emphasis"), "got \(found)")
        XCTAssertTrue(found.contains("emphasis"), "got \(found)")
    }

    func testInlineCodeProducesCodeSpan() async throws {
        let parser = try makeParser()
        let text = "Call `render()` now.\n"
        await parser.parse(text)
        let found = types(await parser.nodes(in: fullRange(text)))
        XCTAssertTrue(found.contains("code_span"), "got \(found)")
    }

    func testFencedCodeBlockIsDetected() async throws {
        let parser = try makeParser()
        let text = "```swift\nlet x = 1\n```\n"
        await parser.parse(text)
        let found = types(await parser.nodes(in: fullRange(text)))
        XCTAssertTrue(found.contains("fenced_code_block"), "got \(found)")
    }

    func testLinkIsDetected() async throws {
        let parser = try makeParser()
        let text = "See [label](https://example.com) here.\n"
        await parser.parse(text)
        let found = types(await parser.nodes(in: fullRange(text)))
        XCTAssertTrue(found.contains("inline_link"), "got \(found)")
    }

    func testListAndBlockquoteAreDetected() async throws {
        let parser = try makeParser()
        let text = "- one\n- two\n\n> quoted\n"
        await parser.parse(text)
        let found = types(await parser.nodes(in: fullRange(text)))
        XCTAssertTrue(found.contains("list"), "got \(found)")
        XCTAssertTrue(found.contains("block_quote"), "got \(found)")
    }

    // MARK: - Ranges

    func testHeadingRangeCoversTheLine() async throws {
        let parser = try makeParser()
        let text = "# Title\nbody\n"
        await parser.parse(text)
        let nodes = await parser.nodes(in: fullRange(text))
        guard let heading = nodes.first(where: { $0.type == "atx_heading" }) else {
            return XCTFail("no atx_heading node")
        }
        // The heading node should start at offset 0 and cover "# Title".
        XCTAssertEqual(heading.range.location, 0)
        XCTAssertGreaterThanOrEqual(heading.range.length, 7)
        let ns = text as NSString
        XCTAssertTrue(ns.substring(with: heading.range).hasPrefix("# Title"))
    }

    // MARK: - Incremental reparse correctness

    func testIncrementalEditUpdatesTree() async throws {
        let parser = try makeParser()
        let original = "Plain paragraph.\n"
        await parser.parse(original)
        var before = types(await parser.nodes(in: fullRange(original)))
        XCTAssertFalse(before.contains("atx_heading"))

        // Insert "# " at the very start, turning the line into a heading.
        let edited = "# Plain paragraph.\n"
        let edit = MarkdownTextEdit(
            editedRange: NSRange(location: 0, length: 2),  // inserted "# "
            changeInLength: 2)
        await parser.applyEdit(edit, newText: edited)

        let after = types(await parser.nodes(in: fullRange(edited)))
        XCTAssertTrue(
            after.contains("atx_heading"), "incremental reparse missed heading; got \(after)")
        before = after  // silence unused-mutation warning
        _ = before
    }

    func testIncrementalEditWithoutPriorParseFallsBackToFull() async throws {
        let parser = try makeParser()
        // No parse() first — applyEdit must fall back to a full parse.
        let text = "# Heading\n"
        await parser.applyEdit(
            MarkdownTextEdit(editedRange: fullRange(text), changeInLength: text.utf16.count),
            newText: text)
        let found = types(await parser.nodes(in: fullRange(text)))
        XCTAssertTrue(found.contains("atx_heading"), "got \(found)")
    }

    // MARK: - Latency

    /// Incremental reparse after a single-character insertion must stay far
    /// under one 16 ms frame, even on a large document.
    func testIncrementalReparseLatencyUnderBudget() async throws {
        let parser = try makeParser()
        var text = String(
            repeating: "# Heading\n\nSome **bold** paragraph text here.\n\n", count: 2_000)
        await parser.parse(text)

        // Insert one character at the head and reparse incrementally, measuring.
        let iterations = 50
        let clock = ContinuousClock()
        var total: Duration = .zero
        for _ in 0..<iterations {
            text = "x" + text
            let edit = MarkdownTextEdit(
                editedRange: NSRange(location: 0, length: 1),
                changeInLength: 1)
            let elapsed = await clock.measure {
                await parser.applyEdit(edit, newText: text)
            }
            total += elapsed
        }
        let mean = total / iterations
        let meanSeconds =
            Double(mean.components.attoseconds) / 1e18
            + Double(mean.components.seconds)
        print("P2.0.1 incremental reparse mean: \(meanSeconds * 1000) ms over \(iterations) edits")
        XCTAssertLessThan(meanSeconds, 0.016, "incremental reparse exceeded one frame")
    }
}
