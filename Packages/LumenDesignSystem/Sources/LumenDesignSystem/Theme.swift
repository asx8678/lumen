//
//  Theme.swift
//  LumenDesignSystem
//
//  Resolves design tokens into usable colors. When appearance is `.system`,
//  colors are dynamic (follow the effective appearance at draw time); otherwise
//  they are fixed to the chosen palette so an explicit dark/light override wins.
//

import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

/// A semantic color role resolved by ``Theme``.
public enum ColorRole: Sendable, CaseIterable {
    case windowBackground
    case surfaceBackground
    case sidebarBackground
    case editorBackground
    case activeLineBackground
    case textPrimary
    case textSecondary
    case textPlaceholder
    case separator
    case separatorHover
    case hoverWash
    case activeWash
    case linkAccent

    /// The component of a `Palette` this role maps to.
    func value(in palette: Palette) -> RGBA {
        switch self {
        case .windowBackground: palette.windowBackground
        case .surfaceBackground: palette.surfaceBackground
        case .sidebarBackground: palette.sidebarBackground
        case .editorBackground: palette.editorBackground
        case .activeLineBackground: palette.activeLineBackground
        case .textPrimary: palette.textPrimary
        case .textSecondary: palette.textSecondary
        case .textPlaceholder: palette.textPlaceholder
        case .separator: palette.separator
        case .separatorHover: palette.separatorHover
        case .hoverWash: palette.hoverWash
        case .activeWash: palette.activeWash
        case .linkAccent: palette.linkAccent
        }
    }
}

/// The resolved theme: appearance + accent, with token accessors.
public struct Theme: Sendable, Equatable {
    public let appearance: Appearance
    public let accent: AccentColor

    public init(appearance: Appearance = .system, accent: AccentColor = .blue) {
        self.appearance = appearance
        self.accent = accent
    }

    /// The concrete palette for this theme's resolved appearance.
    public var palette: Palette { Palette.resolved(appearance.resolved) }

    /// The accent color value.
    public var accentRGBA: RGBA { accent.rgba }

    /// The SwiftUI accent `Color`.
    public var accentColor: Color { accent.rgba.color }

    // MARK: - SwiftUI colors

    /// A SwiftUI `Color` for a semantic role.
    public func color(_ role: ColorRole) -> Color {
        #if canImport(AppKit)
        return Color(nsColor: nsColor(role))
        #else
        return role.value(in: palette).color
        #endif
    }

    #if canImport(AppKit)
    /// An `NSColor` for a semantic role. Dynamic (appearance-following) when
    /// the appearance is `.system`; otherwise fixed to the chosen palette.
    public func nsColor(_ role: ColorRole) -> NSColor {
        switch appearance {
        case .system:
            return NSColor(name: nil) { appearance in
                let isDark =
                    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                let palette = Palette.resolved(isDark ? .dark : .light)
                return role.value(in: palette).nsColor
            }
        case .dark, .light:
            return role.value(in: palette).nsColor
        }
    }
    #endif
}
