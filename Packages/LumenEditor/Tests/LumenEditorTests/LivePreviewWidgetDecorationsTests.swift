//
//  LivePreviewWidgetDecorationsTests.swift
//  LumenEditorTests
//
//  P2.2.1d (lumen-nmm.20) — pure-logic tests for Widget-class live-preview
//  decorations: widget range extraction per node type (link, image, HR) and
//  text scan (wikilink, embed), the wikilink display-label rule, the active-
//  line revert decision, and caret/selection atomicity over widget ranges.
//  Mirrors the headless style of LivePreviewDecorationsTests.
//

import AppKit
import XCTest

@testable import LumenEditor

final class LivePreviewWidgetDecorationsTests: XCTestCase {
    private func parse(_ text: String) async throws -> [MarkdownSyntaxNode] {
        let parser = try MarkdownTreeSitterParser()
        await parser.parse(text)
        return await parser.nodes(in: NSRange(location: 0, length: (text as NSString).length))
    }

    private func widgets(_ text: String) async throws -> [LivePreviewWidgetDecorations.Widget] {
        let nodes = try await parse(text)
        return LivePreviewWidgetDecorations.widgets(from: nodes, in: text as NSString)
    }

    // MARK: - Link

    func testInlineLinkWidget() async throws {
        let text = "see [Apple](https://apple.com) here"
        let ws = try await widgets(text)
        guard
            let link = ws.first(where: {
                if case .link = $0.kind { return true } else { return false }
            })
        else { return XCTFail("no link widget: \(ws)") }
        XCTAssertEqual(link.displayLabel, "Apple")
        XCTAssertEqual(link.kind, .link(url: "https://apple.com"))
        let ns = text as NSString
        XCTAssertEqual(ns.substring(with: link.sourceRange), "[Apple](https://apple.com)")
    }

    // MARK: - Image

    func testInlineImageWidget() async throws {
        let text = "![A cat](cats/tabby.png)"
        let ws = try await widgets(text)
        guard
            let image = ws.first(where: {
                if case .image = $0.kind { return true } else { return false }
            })
        else { return XCTFail("no image widget: \(ws)") }
        XCTAssertEqual(image.kind, .image(url: "cats/tabby.png", isEmbed: false))
        XCTAssertEqual(image.displayLabel, "A cat")
    }

    func testImageEmbedWidget() async throws {
        let text = "![[diagram.png]]"
        let ws = try await widgets(text)
        guard
            let image = ws.first(where: {
                if case .image(_, let isEmbed) = $0.kind { return isEmbed } else { return false }
            })
        else { return XCTFail("no embed widget: \(ws)") }
        XCTAssertEqual(image.kind, .image(url: "diagram.png", isEmbed: true))
        XCTAssertEqual(image.displayLabel, "diagram.png")
        XCTAssertEqual((text as NSString).substring(with: image.sourceRange), "![[diagram.png]]")
    }

    // MARK: - Wikilink

    func testWikilinkVariantsLabel() {
        XCTAssertEqual(LivePreviewWidgetDecorations.wikilinkLabel(for: "Note"), "Note")
        XCTAssertEqual(LivePreviewWidgetDecorations.wikilinkLabel(for: "folder/Note"), "Note")
        XCTAssertEqual(LivePreviewWidgetDecorations.wikilinkLabel(for: "Note|Alias"), "Alias")
        XCTAssertEqual(LivePreviewWidgetDecorations.wikilinkLabel(for: "Note#Heading"), "Heading")
        XCTAssertEqual(LivePreviewWidgetDecorations.wikilinkLabel(for: "Note#^block1"), "block1")
        XCTAssertEqual(
            LivePreviewWidgetDecorations.wikilinkLabel(for: "a/b/Note#H"), "H")
    }

    func testWikilinkWidgetSourceRangeAndKind() async throws {
        let text = "link to [[My Note|alias]] please"
        let ws = try await widgets(text)
        guard
            let wiki = ws.first(where: {
                if case .wikilink = $0.kind { return true } else { return false }
            })
        else { return XCTFail("no wikilink: \(ws)") }
        XCTAssertEqual(wiki.kind, .wikilink(target: "My Note|alias"))
        XCTAssertEqual(wiki.displayLabel, "alias")
        XCTAssertEqual((text as NSString).substring(with: wiki.sourceRange), "[[My Note|alias]]")
    }

    func testUnbalancedWikilinkStaysRaw() {
        let text = "typing [[Half" as NSString
        XCTAssertTrue(LivePreviewWidgetDecorations.wikilinkWidgets(in: text).isEmpty)
    }

    func testEscapedWikilinkOpenIgnored() {
        let text = "\\[[NotALink]]" as NSString
        // The first `[` is escaped, so no widget opens at that index.
        let ws = LivePreviewWidgetDecorations.wikilinkWidgets(in: text)
        XCTAssertTrue(ws.allSatisfy { $0.sourceRange.location != 0 })
    }

    func testWikilinkDoesNotCrossNewline() {
        let text = "[[open\nclose]]" as NSString
        XCTAssertTrue(LivePreviewWidgetDecorations.wikilinkWidgets(in: text).isEmpty)
    }

    // MARK: - Horizontal rule

    func testThematicBreakWidget() async throws {
        let text = "para\n\n---\n\nmore\n"
        let ws = try await widgets(text)
        guard let hr = ws.first(where: { $0.kind == .horizontalRule }) else {
            return XCTFail("no HR widget: \(ws)")
        }
        XCTAssertEqual((text as NSString).substring(with: hr.sourceRange), "---")
    }

    func testFrontmatterIsNotHorizontalRule() async throws {
        let text = "---\ntitle: x\n---\n\nbody\n"
        let ws = try await widgets(text)
        XCTAssertFalse(ws.contains { $0.kind == .horizontalRule }, "frontmatter misread as HR")
    }

    func testSetextUnderlineIsNotHorizontalRule() async throws {
        let text = "Title\n---\n\nbody\n"
        let ws = try await widgets(text)
        XCTAssertFalse(ws.contains { $0.kind == .horizontalRule }, "setext misread as HR")
    }

    // MARK: - Active-line revert

    func testWidgetRevertsOnActiveLine() async throws {
        let text = "alpha\n[Apple](https://apple.com)\nbravo"
        let ns = text as NSString
        let all = try await widgets(text)
        XCTAssertFalse(all.isEmpty)

        // Caret on line 0 (alpha): the link renders.
        let inactive = LivePreviewWidgetDecorations.resolve(
            in: ns, selections: [NSRange(location: 0, length: 0)], widgets: all)
        XCTAssertEqual(inactive.rendered.count, all.count)
        XCTAssertTrue(inactive.reverted.isEmpty)

        // Caret inside the link's line: it reverts to raw source.
        let linkLoc = ns.range(of: "Apple").location
        let active = LivePreviewWidgetDecorations.resolve(
            in: ns, selections: [NSRange(location: linkLoc, length: 0)], widgets: all)
        XCTAssertTrue(active.rendered.isEmpty)
        XCTAssertEqual(active.reverted.count, all.count)
    }

    // MARK: - Caret atomicity over widget ranges

    func testCaretSnapsOverWidgetRange() {
        // A widget occupying [4, 10) — a caret proposed inside snaps to an edge.
        let widget = NSRange(location: 4, length: 6)
        let insideForward = LivePreviewCaretNavigation.adjustedSelection(
            proposed: NSRange(location: 6, length: 0),
            previous: NSRange(location: 4, length: 0),
            concealed: [widget],
            length: 40)
        XCTAssertEqual(insideForward, NSRange(location: 10, length: 0))

        let insideBackward = LivePreviewCaretNavigation.adjustedSelection(
            proposed: NSRange(location: 7, length: 0),
            previous: NSRange(location: 12, length: 0),
            concealed: [widget],
            length: 40)
        XCTAssertEqual(insideBackward, NSRange(location: 4, length: 0))
    }

    func testSelectionExpandsToCoverWidget() {
        let widget = NSRange(location: 4, length: 6)
        // A selection cutting through the widget snaps outward to cover it.
        let adjusted = LivePreviewCaretNavigation.adjustedSelection(
            proposed: NSRange(location: 6, length: 2),
            previous: NSRange(location: 6, length: 0),
            concealed: [widget],
            length: 40)
        XCTAssertEqual(adjusted, NSRange(location: 4, length: 6))
    }

    // MARK: - Source ranges helper

    func testSourceRangesSorted() async throws {
        let text = "[A](u) and [[B]] and ![c](d)"
        let all = try await widgets(text)
        let ranges = LivePreviewWidgetDecorations.sourceRanges(of: all)
        XCTAssertEqual(ranges, ranges.sorted { $0.location < $1.location })
        XCTAssertEqual(ranges.count, all.count)
    }
}
