//
//  Appearance.swift
//  LumenDesignSystem
//
//  Appearance selection (dark default) and accent presets.
//

import SwiftUI

/// The user's appearance preference. `system` follows macOS; Lumen defaults to
/// dark when resolving an explicit palette.
public enum Appearance: String, Sendable, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    /// Human-readable label for pickers.
    public var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// The concrete palette appearance to resolve to. `system` resolves to
    /// `dark` per Lumen's dark-by-default stance (the live UI additionally uses
    /// dynamic colors so true system following still works).
    public var resolved: ResolvedAppearance {
        switch self {
        case .light: .light
        case .dark, .system: .dark
        }
    }

    /// The SwiftUI `ColorScheme` to force, or `nil` to follow the system.
    public var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// A concrete (non-`system`) appearance used to pick a palette.
public enum ResolvedAppearance: Sendable {
    case light
    case dark
}

/// A small set of selectable accent colors (single accent at a time).
public enum AccentColor: String, Sendable, Codable, CaseIterable, Identifiable {
    case blue
    case purple
    case pink
    case green
    case orange
    case graphite

    public var id: String { rawValue }

    public var label: String { rawValue.capitalized }

    /// The accent's color value.
    public var rgba: RGBA {
        switch self {
        case .blue: RGBA(r: 10, g: 132, b: 255)
        case .purple: RGBA(r: 191, g: 90, b: 242)
        case .pink: RGBA(r: 255, g: 55, b: 95)
        case .green: RGBA(r: 50, g: 215, b: 75)
        case .orange: RGBA(r: 255, g: 159, b: 10)
        case .graphite: RGBA(r: 152, g: 152, b: 157)
        }
    }
}
