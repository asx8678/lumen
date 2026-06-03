//
//  ThemeManager.swift
//  LumenDesignSystem
//
//  Observable theming engine: holds the selected appearance + accent, persists
//  them to UserDefaults, and vends a resolved `Theme`. Inject into the SwiftUI
//  environment and apply `preferredColorScheme` + `.tint(accent)` at the
//  app/window level.
//

import Observation
import SwiftUI

/// Observable manager for appearance + accent, persisted across launches.
@MainActor
@Observable
public final class ThemeManager {
    /// The selected appearance (dark by default).
    public var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }

    /// The selected accent color.
    public var accent: AccentColor {
        didSet { defaults.set(accent.rawValue, forKey: Self.accentKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    private static let appearanceKey = "LumenDesignSystem.appearance"
    private static let accentKey = "LumenDesignSystem.accent"

    /// Creates a manager, loading persisted values (default: dark + blue).
    /// - Parameter defaults: Persistence store (injectable for tests).
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedAppearance = defaults.string(forKey: Self.appearanceKey)
            .flatMap(Appearance.init(rawValue:))
        let storedAccent = defaults.string(forKey: Self.accentKey)
            .flatMap(AccentColor.init(rawValue:))
        self.appearance = storedAppearance ?? .dark
        self.accent = storedAccent ?? .blue
    }

    /// The current resolved theme.
    public var theme: Theme {
        Theme(appearance: appearance, accent: accent)
    }

    /// The `ColorScheme` to force at the app level, or `nil` to follow system.
    public var preferredColorScheme: ColorScheme? {
        appearance.preferredColorScheme
    }
}
