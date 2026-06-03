//
//  ThemeTests.swift
//  LumenDesignSystemTests
//
//  P1.17: token resolution per appearance, accent persistence, and theme
//  selection/persistence.
//

import Foundation
import XCTest

@testable import LumenDesignSystem

final class ThemeTests: XCTestCase {
    // MARK: - Token resolution

    func testDarkAndLightPalettesDiffer() {
        XCTAssertNotEqual(Palette.dark.windowBackground, Palette.light.windowBackground)
        XCTAssertNotEqual(Palette.dark.textPrimary, Palette.light.textPrimary)
    }

    func testAppearanceResolvesSystemToDark() {
        XCTAssertEqual(Appearance.system.resolved, .dark)
        XCTAssertEqual(Appearance.dark.resolved, .dark)
        XCTAssertEqual(Appearance.light.resolved, .light)
    }

    func testResolvedPaletteMatchesAppearance() {
        XCTAssertEqual(Palette.resolved(.dark), Palette.dark)
        XCTAssertEqual(Palette.resolved(.light), Palette.light)
    }

    func testThemePaletteFollowsAppearance() {
        XCTAssertEqual(Theme(appearance: .light).palette, Palette.light)
        XCTAssertEqual(Theme(appearance: .dark).palette, Palette.dark)
        XCTAssertEqual(Theme(appearance: .system).palette, Palette.dark)
    }

    func testColorRoleMapping() {
        let dark = Palette.dark
        XCTAssertEqual(ColorRole.windowBackground.value(in: dark), dark.windowBackground)
        XCTAssertEqual(ColorRole.textPrimary.value(in: dark), dark.textPrimary)
        XCTAssertEqual(ColorRole.separator.value(in: dark), dark.separator)
        XCTAssertEqual(ColorRole.activeLineBackground.value(in: dark), dark.activeLineBackground)
        XCTAssertEqual(ColorRole.hoverWash.value(in: dark), dark.hoverWash)
        XCTAssertEqual(ColorRole.activeWash.value(in: dark), dark.activeWash)
        XCTAssertEqual(ColorRole.linkAccent.value(in: dark), dark.linkAccent)
    }

    /// Every `ColorRole` must resolve in both palettes (guards new roles).
    func testAllColorRolesResolve() {
        for role in ColorRole.allCases {
            _ = role.value(in: Palette.dark)
            _ = role.value(in: Palette.light)
        }
        XCTAssertEqual(ColorRole.allCases.count, 13)
    }

    // MARK: - Obsidian elevation + token contract

    /// The elevation rule: chrome (sidebar/window) is DARKER than the focal
    /// editor; wells are darker still; the active-line row sits between.
    func testDarkElevationOrdering() {
        let p = Palette.dark
        XCTAssertLessThan(p.surfaceBackground.red, p.windowBackground.red)
        XCTAssertLessThan(p.windowBackground.red, p.activeLineBackground.red)
        XCTAssertLessThan(p.activeLineBackground.red, p.editorBackground.red)
        XCTAssertEqual(p.sidebarBackground, p.windowBackground)
    }

    func testDarkObsidianTokenValues() {
        let p = Palette.dark
        XCTAssertEqual(p.editorBackground, RGBA(r: 30, g: 30, b: 30))  // #1E1E1E
        XCTAssertEqual(p.windowBackground, RGBA(r: 22, g: 22, b: 22))  // #161616
        XCTAssertEqual(p.surfaceBackground, RGBA(r: 17, g: 17, b: 17))  // #111111
        XCTAssertEqual(p.separator, RGBA(r: 42, g: 42, b: 42))  // #2A2A2A
        XCTAssertEqual(p.textPrimary, RGBA(r: 218, g: 218, b: 218))  // #DADADA
        XCTAssertEqual(p.textSecondary, RGBA(r: 179, g: 179, b: 179))  // #B3B3B3
        XCTAssertEqual(p.textPlaceholder, RGBA(r: 102, g: 102, b: 102))  // #666666
        XCTAssertEqual(p.linkAccent, RGBA(r: 138, g: 123, b: 239))  // #8A7BEF
        XCTAssertEqual(p.hoverWash, RGBA(255, 255, 255, 0.05))
        XCTAssertEqual(p.activeWash, RGBA(255, 255, 255, 0.08))
    }

    // MARK: - Spacing + radius scales

    func testRadiusScale() {
        XCTAssertEqual(Radius.small, 4)
        XCTAssertEqual(Radius.medium, 8)
        XCTAssertEqual(Radius.large, 12)
    }

    func testSpacingOnFourPointGrid() {
        let grid: [CGFloat] = [
            Spacing.xs, Spacing.sm, Spacing.md, Spacing.lg,
            Spacing.xl, Spacing.xxl, Spacing.xxxl,
        ]
        for value in grid {
            XCTAssertEqual(value.truncatingRemainder(dividingBy: 4), 0, "\(value) off-grid")
        }
        XCTAssertEqual(grid, [4, 8, 12, 16, 20, 24, 32])
    }

    func testTypographyUIScale() {
        XCTAssertEqual(Typography.Style.body.size, 13)
        XCTAssertEqual(Typography.Style.body.weight, .regular)
        XCTAssertEqual(Typography.Style.sectionHeader.size, 13)
        XCTAssertEqual(Typography.Style.sectionHeader.weight, .semibold)
        XCTAssertEqual(Typography.Style.callout.size, 12)
        XCTAssertEqual(Typography.uiLineHeightMultiple, 1.3)
    }

    // MARK: - Accent

    func testAccentColorsAreDistinct() {
        let values = AccentColor.allCases.map(\.rgba)
        XCTAssertEqual(Set(values).count, AccentColor.allCases.count)
    }

    // MARK: - ThemeManager persistence

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "LumenDesignSystemTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @MainActor
    func testThemeManagerDefaultsToDarkBlue() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = ThemeManager(defaults: defaults)
        XCTAssertEqual(manager.appearance, .dark)
        XCTAssertEqual(manager.accent, .blue)
        XCTAssertEqual(manager.preferredColorScheme, .dark)
    }

    @MainActor
    func testThemeManagerPersistsSelections() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = ThemeManager(defaults: defaults)
        first.appearance = .light
        first.accent = .purple

        // A fresh manager on the same store reads the persisted values.
        let second = ThemeManager(defaults: defaults)
        XCTAssertEqual(second.appearance, .light)
        XCTAssertEqual(second.accent, .purple)
        XCTAssertEqual(second.theme.accentRGBA, AccentColor.purple.rgba)
    }

    @MainActor
    func testPreferredColorSchemeMapping() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = ThemeManager(defaults: defaults)
        manager.appearance = .system
        XCTAssertNil(manager.preferredColorScheme)
        manager.appearance = .light
        XCTAssertEqual(manager.preferredColorScheme, .light)
        manager.appearance = .dark
        XCTAssertEqual(manager.preferredColorScheme, .dark)
    }
}
