//
//  LivePreviewBlockChromeTests.swift
//  LumenEditorTests
//
//  P2.2.1c (lumen-nmm.19) — mechanism tests for block-level chrome:
//  * the content-storage delegate substitutes bullet glyphs and applies
//    paragraph indentation in the DISPLAY string (backing store untouched);
//  * the layout-manager delegate vends a chrome fragment for blockquote /
//    code paragraphs and a plain fragment elsewhere.
//

import AppKit
import XCTest

@testable import LumenEditor

@MainActor
final class LivePreviewBlockChromeTests: XCTestCase {
    private func makeStack(
        _ text: String,
        controller: LivePreviewConcealmentController
    ) -> (NSTextLayoutManager, NSTextContentStorage) {
        let contentStorage = NSTextContentStorage()
        contentStorage.delegate = controller
        let layoutManager = NSTextLayoutManager()
        let container = NSTextContainer(
            size: CGSize(width: 2000, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.textContainer = container
        contentStorage.addTextLayoutManager(layoutManager)
        contentStorage.textStorage?.setAttributedString(
            NSAttributedString(
                string: text,
                attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)]))
        return (layoutManager, contentStorage)
    }

    private func displayString(_ layoutManager: NSTextLayoutManager) -> String {
        var result = ""
        layoutManager.enumerateTextLayoutFragments(
            from: layoutManager.documentRange.location, options: [.ensuresLayout]
        ) { fragment in
            result +=
                fragment.textElement.flatMap {
                    ($0 as? NSTextParagraph)?.attributedString.string
                } ?? ""
            return true
        }
        return result
    }

    func testBulletSubstitutionAppearsInDisplayOnly() {
        let controller = LivePreviewConcealmentController()
        controller.isEnabled = true
        let text = "- item\n"
        controller.update(substitutions: [
            .init(range: NSRange(location: 0, length: 2), replacement: "•\u{00A0}")
        ])
        let (layoutManager, storage) = makeStack(text, controller: controller)
        XCTAssertEqual(displayString(layoutManager), "•\u{00A0}item\n")
        // Backing store is still raw Markdown → copy/undo see `- item`.
        XCTAssertEqual(storage.textStorage?.string, text)
    }

    func testParagraphIndentAppliedToDisplay() {
        let controller = LivePreviewConcealmentController()
        controller.isEnabled = true
        let text = "- item\n"
        controller.update(paragraphIndents: [
            .init(anchor: 0, firstLineHeadIndent: 10, headIndent: 28)
        ])
        let (layoutManager, _) = makeStack(text, controller: controller)
        var head: CGFloat = -1
        layoutManager.enumerateTextLayoutFragments(
            from: layoutManager.documentRange.location, options: [.ensuresLayout]
        ) { fragment in
            if let paragraph = fragment.textElement as? NSTextParagraph,
                paragraph.attributedString.length > 0,
                let style = paragraph.attributedString.attribute(
                    .paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            {
                head = style.headIndent
            }
            return true
        }
        XCTAssertEqual(head, 28, accuracy: 0.5)
    }

    func testChromeProviderVendsFragmentForQuoteAndCode() async throws {
        let parser = try MarkdownTreeSitterParser()
        let text = "> quote\n\n```\ncode\n```\n\nplain\n"
        await parser.parse(text)
        let nodes = await parser.nodes(
            in: NSRange(location: 0, length: (text as NSString).length))

        let provider = LivePreviewBlockChromeProvider()
        provider.isEnabled = true
        provider.update(
            blockquotes: LivePreviewBlockDecorations.blockquoteRegions(from: nodes),
            codeBlocks: LivePreviewBlockDecorations.codeBlockRegions(from: nodes))

        let controller = LivePreviewConcealmentController()
        let (layoutManager, _) = makeStack(text, controller: controller)
        layoutManager.delegate = provider

        var quoteIsChrome = false
        var codeIsChrome = false
        var plainIsPlain = true
        layoutManager.enumerateTextLayoutFragments(
            from: layoutManager.documentRange.location, options: [.ensuresLayout]
        ) { fragment in
            let str =
                (fragment.textElement as? NSTextParagraph)?.attributedString.string ?? ""
            let isChrome = fragment is LivePreviewBlockLayoutFragment
            if str.contains("quote") { quoteIsChrome = isChrome }
            if str.contains("code") { codeIsChrome = isChrome }
            if str.contains("plain"), isChrome { plainIsPlain = false }
            return true
        }
        XCTAssertTrue(quoteIsChrome, "blockquote paragraph should get a chrome fragment")
        XCTAssertTrue(codeIsChrome, "code paragraph should get a chrome fragment")
        XCTAssertTrue(plainIsPlain, "ordinary paragraph must stay a plain fragment")
    }
}
