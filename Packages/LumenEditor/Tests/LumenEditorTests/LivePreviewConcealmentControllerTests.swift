//
//  LivePreviewConcealmentControllerTests.swift
//  LumenEditorTests
//
//  P2.2.1 (lumen-nmm.5) SPIKE — proves the TextKit 2 concealment MECHANISM:
//  the content-storage delegate hides marker code units from the *display*
//  paragraph without mutating the backing store, and the resulting layout is
//  geometrically narrower (real glyph removal, not zero-width hacks).
//

import AppKit
import XCTest

@testable import LumenEditor

@MainActor
final class LivePreviewConcealmentControllerTests: XCTestCase {
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

    private func displayString(
        _ layoutManager: NSTextLayoutManager
    ) -> String {
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

    func testDisabledControllerLeavesDisplayVerbatim() {
        let controller = LivePreviewConcealmentController()
        controller.isEnabled = false
        controller.update(concealed: [NSRange(location: 0, length: 2)])
        let text = "**bold**\n"
        let (layoutManager, storage) = makeStack(text, controller: controller)
        XCTAssertEqual(displayString(layoutManager), text)
        XCTAssertEqual(storage.textStorage?.string, text)  // backing untouched
    }

    func testEnabledControllerConcealsMarkersInDisplayOnly() {
        let controller = LivePreviewConcealmentController()
        controller.isEnabled = true
        let text = "**bold**\n"
        // Conceal the leading and trailing `**`.
        controller.update(concealed: [
            NSRange(location: 0, length: 2),
            NSRange(location: 6, length: 2),
        ])
        let (layoutManager, storage) = makeStack(text, controller: controller)
        XCTAssertEqual(displayString(layoutManager), "bold\n", "markers concealed in display")
        // Backing store still holds raw Markdown → copy/undo see real source.
        XCTAssertEqual(storage.textStorage?.string, text)
    }

    func testConcealedDisplayIsGeometricallyNarrower() {
        let text = "**bold**\n"

        let plain = LivePreviewConcealmentController()  // disabled
        let (plainLM, _) = makeStack(text, controller: plain)
        plainLM.ensureLayout(for: plainLM.documentRange)

        let concealing = LivePreviewConcealmentController()
        concealing.isEnabled = true
        concealing.update(concealed: [
            NSRange(location: 0, length: 2),
            NSRange(location: 6, length: 2),
        ])
        let (concealLM, _) = makeStack(text, controller: concealing)
        concealLM.ensureLayout(for: concealLM.documentRange)

        func width(_ lm: NSTextLayoutManager) -> CGFloat {
            var w: CGFloat = 0
            lm.enumerateTextLayoutFragments(
                from: lm.documentRange.location, options: [.ensuresLayout]
            ) { fragment in
                w = max(w, fragment.layoutFragmentFrame.width)
                return true
            }
            return w
        }
        // Removing four `*` glyphs must shrink the laid-out line width — proof
        // the geometry reflects only visible characters (no zero-width tricks).
        XCTAssertLessThan(width(concealLM), width(plainLM))
    }
}
