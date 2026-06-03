//
//  TextMetricsTests.swift
//  LumenCoreTests
//
//  P1.18: pure word/character counting.
//

import XCTest

@testable import LumenCore

final class TextMetricsTests: XCTestCase {
    func testEmpty() {
        let m = TextMetrics(counting: "")
        XCTAssertEqual(m.words, 0)
        XCTAssertEqual(m.characters, 0)
    }

    func testWhitespaceOnly() {
        let m = TextMetrics(counting: "   \n\t  \n")
        XCTAssertEqual(m.words, 0)
        XCTAssertEqual(m.characters, 8)
    }

    func testSimpleSentence() {
        let m = TextMetrics(counting: "the quick brown fox")
        XCTAssertEqual(m.words, 4)
        XCTAssertEqual(m.characters, 19)
    }

    func testMultipleSpacesAndNewlines() {
        let m = TextMetrics(counting: "  hello   world \n\n  again ")
        XCTAssertEqual(m.words, 3)
    }

    func testPunctuationCountsWithinWords() {
        let m = TextMetrics(counting: "well-known, e.g. done.")
        XCTAssertEqual(m.words, 3)  // "well-known," "e.g." "done."
    }

    func testUnicodeGraphemeCount() {
        // "e" + combining acute accent is two scalars but one grapheme cluster.
        let text = "e\u{0301}"  // e-acute (decomposed)
        let m = TextMetrics(counting: text)
        XCTAssertEqual(m.words, 1)
        XCTAssertEqual(m.characters, 1)  // one grapheme, not two scalars
    }

    func testCJKAndAccents() {
        let m = TextMetrics(counting: "café 日本語 test")
        XCTAssertEqual(m.words, 3)
    }
}

extension TextMetricsTests {
    func testSaveStateMapping() {
        XCTAssertEqual(SaveState(isDirty: true), .unsaved)
        XCTAssertEqual(SaveState(isDirty: false), .saved)
        XCTAssertFalse(SaveState.saved.label.isEmpty)
        XCTAssertFalse(SaveState.unsaved.label.isEmpty)
    }
}
