//
//  Palette.swift
//  LumenDesignSystem
//
//  Semantic color tokens for one appearance. Values are tuned to read well over
//  translucent Liquid Glass materials (P1.14): backgrounds are deep but not pure
//  black/white, text uses layered opacities, separators are subtle. Accent is
//  injected separately (configurable), not baked into the palette.
//

import Foundation

/// A complete set of semantic colors for a single appearance.
public struct Palette: Sendable, Equatable {
    // Backgrounds (window/primary, surface/secondary, sidebar).
    public var windowBackground: RGBA
    public var surfaceBackground: RGBA
    public var sidebarBackground: RGBA
    public var editorBackground: RGBA

    // Text (primary, secondary, tertiary/placeholder).
    public var textPrimary: RGBA
    public var textSecondary: RGBA
    public var textPlaceholder: RGBA

    // Lines.
    public var separator: RGBA

    // Markdown syntax-highlight roles (token-driven highlighter colors).
    public var mdHeading: RGBA
    public var mdCode: RGBA
    public var mdFence: RGBA
    public var mdLinkText: RGBA
    public var mdLinkURL: RGBA
    public var mdListMarker: RGBA
    public var mdQuote: RGBA
    public var mdEmphasis: RGBA

    /// The refined dark palette (Lumen's default).
    public static let dark = Palette(
        windowBackground: RGBA(r: 28, g: 28, b: 30),
        surfaceBackground: RGBA(r: 36, g: 36, b: 38),
        sidebarBackground: RGBA(r: 24, g: 24, b: 26),
        editorBackground: RGBA(r: 30, g: 30, b: 32),
        textPrimary: RGBA(r: 235, g: 235, b: 240),
        textSecondary: RGBA(235, 235, 240, 0.62),
        textPlaceholder: RGBA(235, 235, 240, 0.30),
        separator: RGBA(255, 255, 255, 0.10),
        mdHeading: RGBA(r: 100, g: 180, b: 255),
        mdCode: RGBA(r: 255, g: 130, b: 170),
        mdFence: RGBA(235, 235, 240, 0.45),
        mdLinkText: RGBA(r: 90, g: 170, b: 255),
        mdLinkURL: RGBA(r: 90, g: 200, b: 200),
        mdListMarker: RGBA(r: 255, g: 170, b: 80),
        mdQuote: RGBA(235, 235, 240, 0.55),
        mdEmphasis: RGBA(r: 235, g: 235, b: 240)
    )

    /// The light palette.
    public static let light = Palette(
        windowBackground: RGBA(r: 246, g: 246, b: 248),
        surfaceBackground: RGBA(r: 255, g: 255, b: 255),
        sidebarBackground: RGBA(r: 238, g: 238, b: 242),
        editorBackground: RGBA(r: 255, g: 255, b: 255),
        textPrimary: RGBA(r: 28, g: 28, b: 30),
        textSecondary: RGBA(28, 28, 30, 0.62),
        textPlaceholder: RGBA(28, 28, 30, 0.30),
        separator: RGBA(0, 0, 0, 0.10),
        mdHeading: RGBA(r: 0, g: 110, b: 200),
        mdCode: RGBA(r: 200, g: 50, b: 110),
        mdFence: RGBA(28, 28, 30, 0.45),
        mdLinkText: RGBA(r: 0, g: 110, b: 220),
        mdLinkURL: RGBA(r: 0, g: 150, b: 150),
        mdListMarker: RGBA(r: 200, g: 120, b: 0),
        mdQuote: RGBA(28, 28, 30, 0.55),
        mdEmphasis: RGBA(r: 28, g: 28, b: 30)
    )

    /// Returns the palette for a resolved appearance.
    public static func resolved(_ appearance: ResolvedAppearance) -> Palette {
        switch appearance {
        case .dark: dark
        case .light: light
        }
    }
}
