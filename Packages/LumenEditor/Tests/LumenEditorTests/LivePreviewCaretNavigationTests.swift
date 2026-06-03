//
//  LivePreviewCaretNavigationTests.swift
//  LumenEditorTests
//
//  P2.2.1a (lumen-nmm.17) — pure tests for caret atomicity over concealed
//  marker runs: the caret/selection must never split a concealed run.
//

import Foundation
import XCTest

@testable import LumenEditor

final class LivePreviewCaretNavigationTests: XCTestCase {
    // A `**` run hidden at offsets 6...7 (length 2), e.g. mid-document.
    private let concealed = [NSRange(location: 6, length: 2)]

    private func adjust(
        proposed: NSRange,
        previous: NSRange,
        concealed: [NSRange]? = nil,
        length: Int = 100
    ) -> NSRange {
        LivePreviewCaretNavigation.adjustedSelection(
            proposed: proposed,
            previous: previous,
            concealed: concealed ?? self.concealed,
            length: length)
    }

    // MARK: - Bare caret stepping

    func testCaretMovingForwardSkipsToRunEnd() {
        // Caret proposed at 7 (inside the 6..8 run), arriving from the left.
        let result = adjust(
            proposed: NSRange(location: 7, length: 0),
            previous: NSRange(location: 6, length: 0))
        XCTAssertEqual(result, NSRange(location: 8, length: 0))
    }

    func testCaretMovingBackwardSkipsToRunStart() {
        // Caret proposed at 7 (inside the run), arriving from the right.
        let result = adjust(
            proposed: NSRange(location: 7, length: 0),
            previous: NSRange(location: 9, length: 0))
        XCTAssertEqual(result, NSRange(location: 6, length: 0))
    }

    func testCaretAtRunEdgesIsUnchanged() {
        // Edges (6 and 8) are valid landing spots — not strictly inside.
        XCTAssertEqual(
            adjust(
                proposed: NSRange(location: 6, length: 0),
                previous: NSRange(location: 5, length: 0)),
            NSRange(location: 6, length: 0))
        XCTAssertEqual(
            adjust(
                proposed: NSRange(location: 8, length: 0),
                previous: NSRange(location: 9, length: 0)),
            NSRange(location: 8, length: 0))
    }

    func testDirectionlessCaretSnapsToNearerEdge() {
        // A click (previous == proposed) inside the run snaps to nearer edge.
        // Run 6..8; caret 7 is equidistant → ties resolve to the trailing edge.
        XCTAssertEqual(
            adjust(
                proposed: NSRange(location: 7, length: 0),
                previous: NSRange(location: 7, length: 0)),
            NSRange(location: 8, length: 0))
    }

    func testCaretOutsideAnyRunIsUnchanged() {
        let proposed = NSRange(location: 20, length: 0)
        XCTAssertEqual(
            adjust(proposed: proposed, previous: NSRange(location: 19, length: 0)),
            proposed)
    }

    // MARK: - Selection extension (atomic runs)

    func testSelectionEndpointInsideRunExpandsOutward() {
        // Anchor at 0, active end proposed at 7 (inside run) → expand to 8.
        let result = adjust(
            proposed: NSRange(location: 0, length: 7),
            previous: NSRange(location: 0, length: 6))
        XCTAssertEqual(result, NSRange(location: 0, length: 8))
    }

    func testSelectionLowerBoundInsideRunExpandsToRunStart() {
        // Selection 7..20 → lower bound inside run pulls back to 6.
        let result = adjust(
            proposed: NSRange(location: 7, length: 13),
            previous: NSRange(location: 6, length: 14))
        XCTAssertEqual(result, NSRange(location: 6, length: 14))
    }

    func testSelectionSpanningWholeRunIsUnchanged() {
        let proposed = NSRange(location: 0, length: 12)
        XCTAssertEqual(
            adjust(proposed: proposed, previous: NSRange(location: 0, length: 11)),
            proposed)
    }

    // MARK: - Multiple runs & clamping

    func testCaretSkipsCorrectRunAmongMany() {
        let runs = [
            NSRange(location: 2, length: 2),
            NSRange(location: 10, length: 3),
        ]
        // Inside the second run, moving forward → its end (13).
        let result = adjust(
            proposed: NSRange(location: 11, length: 0),
            previous: NSRange(location: 10, length: 0),
            concealed: runs)
        XCTAssertEqual(result, NSRange(location: 13, length: 0))
    }

    func testResultIsClampedToDocumentLength() {
        // Run runs to the very end; forward snap clamps to length.
        let runs = [NSRange(location: 8, length: 2)]
        let result = adjust(
            proposed: NSRange(location: 9, length: 0),
            previous: NSRange(location: 8, length: 0),
            concealed: runs,
            length: 10)
        XCTAssertEqual(result, NSRange(location: 10, length: 0))
    }

    func testEmptyConcealedSetIsNoOp() {
        let proposed = NSRange(location: 7, length: 0)
        XCTAssertEqual(
            adjust(
                proposed: proposed,
                previous: NSRange(location: 6, length: 0),
                concealed: []),
            proposed)
    }
}
