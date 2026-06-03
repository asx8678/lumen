//
//  EditorTypographyTests.swift
//  LumenEditorTests
//
//  P1.13: typography model presets, clamping, persistence round-trip, and the
//  resolved font / paragraph-style values.
//

import AppKit
import XCTest

@testable import LumenEditor

final class EditorTypographyTests: XCTestCase {
    func testDefaults() {
        let t = EditorTypography.default
        XCTAssertEqual(t.fontKind, .monospace)
        XCTAssertEqual(t.lineWidth, .medium)
        XCTAssertGreaterThan(t.fontSize, 0)
    }

    func testFontSizeClampsOnInit() {
        XCTAssertEqual(EditorTypography(fontSize: 2).fontSize, EditorTypography.minFontSize)
        XCTAssertEqual(EditorTypography(fontSize: 999).fontSize, EditorTypography.maxFontSize)
    }

    func testLineSpacingClamps() {
        XCTAssertEqual(
            EditorTypography(lineSpacing: 0.1).lineSpacing, EditorTypography.minLineSpacing)
        XCTAssertEqual(
            EditorTypography(lineSpacing: 9).lineSpacing, EditorTypography.maxLineSpacing)
    }

    func testAdjusters() {
        let base = EditorTypography(fontKind: .monospace, fontSize: 13)
        XCTAssertEqual(base.togglingFontKind().fontKind, .proportional)
        XCTAssertEqual(base.adjustingFontSize(by: 2).fontSize, 15)
        XCTAssertEqual(base.adjustingFontSize(by: -100).fontSize, EditorTypography.minFontSize)
        XCTAssertEqual(base.adjustingFontSize(by: 5).resettingFontSize().fontSize, 13)
    }

    func testLineWidthCycle() {
        XCTAssertEqual(EditorTypography.LineWidth.narrow.next, .medium)
        XCTAssertEqual(EditorTypography.LineWidth.medium.next, .wide)
        XCTAssertEqual(EditorTypography.LineWidth.wide.next, .unlimited)
        XCTAssertEqual(EditorTypography.LineWidth.unlimited.next, .narrow)
        XCTAssertNil(EditorTypography.LineWidth.unlimited.points)
        XCTAssertNotNil(EditorTypography.LineWidth.narrow.points)
    }

    func testResolvedFont() {
        let mono = EditorTypography(fontKind: .monospace, fontSize: 16).resolvedFont()
        XCTAssertEqual(mono.pointSize, 16)
        XCTAssertTrue(mono.fontDescriptor.symbolicTraits.contains(.monoSpace))

        let prop = EditorTypography(fontKind: .proportional, fontSize: 14).resolvedFont()
        XCTAssertEqual(prop.pointSize, 14)
        XCTAssertFalse(prop.fontDescriptor.symbolicTraits.contains(.monoSpace))
    }

    func testResolvedParagraphStyle() {
        let style = EditorTypography(lineSpacing: 1.6).resolvedParagraphStyle()
        XCTAssertEqual(style.lineHeightMultiple, 1.6, accuracy: 0.0001)
    }

    func testCodableRoundTrip() throws {
        let original = EditorTypography(
            fontKind: .proportional, fontSize: 18, lineWidth: .wide, lineSpacing: 1.5)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EditorTypography.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testDecodeClampsOutOfRange() throws {
        // Hand-crafted JSON with an out-of-range size must be clamped on decode.
        let json =
            #"{"fontKind":"monospace","fontSize":500,"lineWidth":"medium","lineSpacing":0.2}"#
        let decoded = try JSONDecoder().decode(
            EditorTypography.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.fontSize, EditorTypography.maxFontSize)
        XCTAssertEqual(decoded.lineSpacing, EditorTypography.minLineSpacing)
    }
}
