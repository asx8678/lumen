//
//  HighlightThemeMappingTests.swift
//  LumenEditorTests
//
//  P1.17: verifies the design-tokens -> MarkdownHighlightTheme mapping.
//

import AppKit
import LumenDesignSystem
import XCTest

@testable import LumenEditor

@MainActor
final class HighlightThemeMappingTests: XCTestCase {
    func testThemeMapsPaletteColors() {
        let palette = Palette.dark
        let highlight = MarkdownHighlightTheme(palette: palette)

        XCTAssertEqual(highlight.headingColor, palette.mdHeading.nsColor)
        XCTAssertEqual(highlight.codeColor, palette.mdCode.nsColor)
        XCTAssertEqual(highlight.linkURLColor, palette.mdLinkURL.nsColor)
        XCTAssertEqual(highlight.bodyColor, palette.textPrimary.nsColor)
    }

    func testDarkAndLightProduceDifferentHeadingColors() {
        let dark = MarkdownHighlightTheme(palette: .dark)
        let light = MarkdownHighlightTheme(palette: .light)
        XCTAssertNotEqual(dark.headingColor, light.headingColor)
    }

    func testInitFromThemeUsesResolvedPalette() {
        let highlight = MarkdownHighlightTheme(theme: Theme(appearance: .light))
        XCTAssertEqual(highlight.headingColor, Palette.light.mdHeading.nsColor)
    }
}
