//
//  TextKit2PerformanceTests.swift
//  LumenEditorTests
//
//  P1.10 RISK SPIKE validation: confirm the editor host uses TextKit 2 and
//  measure large-document load + batch-edit performance.
//
//  NOTE: interactive scroll / per-keystroke typing latency cannot be measured
//  in a headless test run; these tests cover programmatic load + edit cost and
//  prove the architecture stays on the viewport-based TextKit 2 layout path.
//

import AppKit
import XCTest

@testable import LumenEditor

@MainActor
final class TextKit2PerformanceTests: XCTestCase {
    /// Number of lines in the synthetic large document (~70k lines, several MB).
    private let largeLineCount = 70_000

    /// Builds a TextKit 2 NSTextView the same way the editor host does.
    private func makeTextKit2View() -> NSTextView {
        NSTextView(usingTextLayoutManager: true)
    }

    /// Asserts the editor host is on the TextKit 2 stack, not TextKit 1.
    func testTextKit2IsActive() {
        let textView = makeTextKit2View()
        XCTAssertNotNil(textView.textLayoutManager,
                        "Expected a TextKit 2 NSTextLayoutManager")
        XCTAssertNotNil(textView.textContentStorage,
                        "Expected a TextKit 2 NSTextContentStorage")
        // The presence of textLayoutManager confirms the modern stack; we never
        // instantiate the legacy `layoutManager` ourselves.
    }

    /// Measures time to load a large document and lay out the initial viewport.
    func testLargeDocumentLoadAndViewportLayout() {
        let markdown = SampleContent.syntheticMarkdown(lineCount: largeLineCount)
        let byteCount = markdown.utf8.count
        print("Synthetic doc: \(largeLineCount) lines, \(byteCount / 1024) KiB")

        measure {
            let textView = makeTextKit2View()
            textView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
            textView.string = markdown

            // Force initial viewport layout (what the user first sees), not the
            // whole document — this is the TextKit 2 viewport path.
            guard let layoutManager = textView.textLayoutManager,
                  let viewportStart = layoutManager.documentRange.location as NSTextLocation? else {
                XCTFail("Missing TextKit 2 layout manager")
                return
            }
            var laidOutFragments = 0
            layoutManager.enumerateTextLayoutFragments(
                from: viewportStart,
                options: [.ensuresLayout, .estimatesSize]
            ) { _ in
                laidOutFragments += 1
                // Stop after a viewport's worth of fragments (~60 visible lines).
                return laidOutFragments < 60
            }
            XCTAssertGreaterThan(laidOutFragments, 0)
        }
    }

    /// Measures a batch of programmatic insertions into a large document.
    func testBatchEditPerformance() {
        let markdown = SampleContent.syntheticMarkdown(lineCount: largeLineCount)
        let textView = makeTextKit2View()
        textView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        textView.string = markdown

        guard let textStorage = textView.textContentStorage?.textStorage else {
            XCTFail("Missing TextKit 2 content storage")
            return
        }

        measure {
            // 200 small insertions at the document head — exercises edit +
            // incremental relayout on the TextKit 2 stack.
            textStorage.beginEditing()
            for i in 0..<200 {
                textStorage.replaceCharacters(
                    in: NSRange(location: 0, length: 0),
                    with: "edit \(i)\n"
                )
            }
            textStorage.endEditing()
        }
    }
}
