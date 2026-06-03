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
