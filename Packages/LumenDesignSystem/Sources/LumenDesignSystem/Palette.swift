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
///
/// Tuned to Obsidian's default-dark in the dark variant (Phase-1 chrome pass):
/// the elevation rule that matters most is that *chrome* surfaces (sidebar, tab
/// bar, status bar) sit a few small, uniform steps DARKER than the focal editor,
/// with subtle 1px borders. Interaction is expressed with neutral white-washes
/// (hover/active), NOT the accent — the accent stays reserved for focus rings,
/// prominent buttons, and the dirty-dot.
public struct Palette: Sendable, Equatable {
    // Backgrounds.
    /// Chrome surface (sidebar / tab bar / status bar). Darkest "shell" layer.
    public var windowBackground: RGBA
    /// Recessed wells (search fields, inputs). Slightly darker than chrome.
    public var surfaceBackground: RGBA
    /// Sidebar chrome surface (matches window chrome).
    public var sidebarBackground: RGBA
    /// Focal content surface (the editor). Lightest of the elevation steps.
    public var editorBackground: RGBA
    /// Active-line / alternate-row fill (one small step above the editor).
    public var activeLineBackground: RGBA

    // Text (primary/normal, secondary/muted, tertiary/faint placeholder).
    public var textPrimary: RGBA
    public var textSecondary: RGBA
    public var textPlaceholder: RGBA

    // Lines.
    /// Default 1px separator / border.
    public var separator: RGBA
    /// Hover-state separator / border (slightly brighter).
    public var separatorHover: RGBA

    // Interaction washes (neutral, NOT accent-tinted).
    /// Row hover wash (e.g. white @ 5% in dark).
    public var hoverWash: RGBA
    /// Active / pressed / selected wash (e.g. white @ 8% in dark).
    public var activeWash: RGBA

    /// Text/link accent (distinct from the interactive accent; ~#8A7BEF dark).
    public var linkAccent: RGBA

    // Markdown syntax-highlight roles (token-driven highlighter colors).
    public var mdHeading: RGBA
    public var mdCode: RGBA
    public var mdFence: RGBA
    public var mdLinkText: RGBA
    public var mdLinkURL: RGBA
    public var mdListMarker: RGBA
    public var mdQuote: RGBA
    public var mdEmphasis: RGBA

    /// The Obsidian-style default-dark palette (Lumen's default).
    public static let dark = Palette(
        windowBackground: RGBA(r: 22, g: 22, b: 22),  // #161616 chrome
        surfaceBackground: RGBA(r: 17, g: 17, b: 17),  // #111111 wells
        sidebarBackground: RGBA(r: 22, g: 22, b: 22),  // #161616 chrome
        editorBackground: RGBA(r: 30, g: 30, b: 30),  // #1E1E1E focal
        activeLineBackground: RGBA(r: 26, g: 26, b: 26),  // #1A1A1A alt rows
        textPrimary: RGBA(r: 218, g: 218, b: 218),  // #DADADA normal
        textSecondary: RGBA(r: 179, g: 179, b: 179),  // #B3B3B3 muted
        textPlaceholder: RGBA(r: 102, g: 102, b: 102),  // #666666 faint
        separator: RGBA(r: 42, g: 42, b: 42),  // #2A2A2A border
        separatorHover: RGBA(r: 54, g: 54, b: 54),  // #363636 border hover
        hoverWash: RGBA(255, 255, 255, 0.05),  // white @ 5%
        activeWash: RGBA(255, 255, 255, 0.08),  // white @ 8%
        linkAccent: RGBA(r: 138, g: 123, b: 239),  // #8A7BEF
        mdHeading: RGBA(r: 100, g: 180, b: 255),
        mdCode: RGBA(r: 255, g: 130, b: 170),
        mdFence: RGBA(218, 218, 218, 0.45),
        mdLinkText: RGBA(r: 138, g: 123, b: 239),  // #8A7BEF link accent
        mdLinkURL: RGBA(r: 90, g: 200, b: 200),
        mdListMarker: RGBA(r: 255, g: 170, b: 80),
        mdQuote: RGBA(218, 218, 218, 0.55),
        mdEmphasis: RGBA(r: 218, g: 218, b: 218)
    )

    /// The light palette (lightly aligned to the same elevation/role model:
    /// chrome a touch darker than the focal editor, neutral washes, subtle
    /// borders). Kept fully working for the light appearance.
    public static let light = Palette(
        windowBackground: RGBA(r: 240, g: 240, b: 242),  // chrome
        surfaceBackground: RGBA(r: 233, g: 233, b: 236),  // wells
        sidebarBackground: RGBA(r: 240, g: 240, b: 242),  // chrome
        editorBackground: RGBA(r: 255, g: 255, b: 255),  // focal
        activeLineBackground: RGBA(r: 245, g: 245, b: 247),  // alt rows
        textPrimary: RGBA(r: 28, g: 28, b: 30),
        textSecondary: RGBA(28, 28, 30, 0.62),
        textPlaceholder: RGBA(28, 28, 30, 0.34),
        separator: RGBA(0, 0, 0, 0.12),
        separatorHover: RGBA(0, 0, 0, 0.20),
        hoverWash: RGBA(0, 0, 0, 0.04),  // black @ 4%
        activeWash: RGBA(0, 0, 0, 0.08),  // black @ 8%
        linkAccent: RGBA(r: 88, g: 74, b: 200),  // darker violet for light
        mdHeading: RGBA(r: 0, g: 110, b: 200),
        mdCode: RGBA(r: 200, g: 50, b: 110),
        mdFence: RGBA(28, 28, 30, 0.45),
        mdLinkText: RGBA(r: 88, g: 74, b: 200),
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
