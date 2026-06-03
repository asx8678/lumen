//
//  LivePreviewWidgetRenderingTests.swift
//  LumenEditorTests
//
//  lumen-gia: mechanism checks for the image widget rendering — real pixels
//  become a text attachment, a missing image falls back to a placeholder.
//

import AppKit
import XCTest

@testable import LumenEditor

final class LivePreviewWidgetRenderingTests: XCTestCase {
    private func imageWidget() -> LivePreviewWidgetDecorations.Widget {
        .init(
            sourceRange: NSRange(location: 0, length: 10),
            kind: .image(url: "pic.png", isEmbed: false),
            displayLabel: "A cat")
    }

    func testImageWithPixelsRendersAttachment() {
        let pixels = NSImage(size: NSSize(width: 120, height: 60))
        let string = LivePreviewWidgetRendering.attributedString(
            for: imageWidget(),
            font: .systemFont(ofSize: 14),
            linkColor: .linkColor,
            ruleColor: .gray,
            placeholderColor: .gray,
            width: 600,
            image: pixels)
        var hasAttachment = false
        string.enumerateAttribute(
            .attachment, in: NSRange(location: 0, length: string.length)
        ) { value, _, _ in
            if value is NSTextAttachment { hasAttachment = true }
        }
        XCTAssertTrue(hasAttachment, "expected an image attachment")
    }

    func testImageScaledDownToMaxWidth() {
        let pixels = NSImage(size: NSSize(width: 1000, height: 500))
        let string = LivePreviewWidgetRendering.attributedString(
            for: imageWidget(),
            font: .systemFont(ofSize: 14),
            linkColor: .linkColor,
            ruleColor: .gray,
            placeholderColor: .gray,
            width: 600,
            image: pixels,
            maxImageWidth: 300)
        guard
            let attachment = string.attribute(.attachment, at: 0, effectiveRange: nil)
                as? NSTextAttachment
        else { return XCTFail("no attachment") }
        XCTAssertEqual(attachment.bounds.width, 300, accuracy: 0.5)
        XCTAssertEqual(attachment.bounds.height, 150, accuracy: 0.5)
    }

    func testMissingImageFallsBackToPlaceholder() {
        let string = LivePreviewWidgetRendering.attributedString(
            for: imageWidget(),
            font: .systemFont(ofSize: 14),
            linkColor: .linkColor,
            ruleColor: .gray,
            placeholderColor: .gray,
            width: 600,
            image: nil)
        XCTAssertTrue(string.string.contains("A cat"))
        XCTAssertNil(string.attribute(.attachment, at: 0, effectiveRange: nil))
    }
}
