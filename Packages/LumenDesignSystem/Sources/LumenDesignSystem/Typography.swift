//
//  Typography.swift
//  LumenDesignSystem
//
//  A semantic type scale + a monospace family for code. These are the scale
//  TOKENS; the editor's *adjustable* font/line-width/spacing controls are P1.13.
//

import SwiftUI

/// The app's type scale. Sizes are points; the SwiftUI `Font` accessors use the
/// system face (and a monospaced face for code).
public enum Typography {
    /// A named step in the type scale. UI sizes match Obsidian-class chrome:
    /// file rows & tab labels = `body` (13/regular), section headers =
    /// `sectionHeader` (13/semibold, render in a muted tint), status bar =
    /// `callout` (12/regular).
    public enum Style: Sendable, CaseIterable {
        case largeTitle
        case title
        case headline
        case sectionHeader
        case body
        case callout
        case caption

        /// Point size for the style.
        public var size: CGFloat {
            switch self {
            case .largeTitle: 26
            case .title: 20
            case .headline: 15
            case .sectionHeader: 13
            case .body: 13
            case .callout: 12
            case .caption: 11
            }
        }

        /// Font weight for the style.
        public var weight: Font.Weight {
            switch self {
            case .largeTitle, .title: .semibold
            case .headline, .sectionHeader: .semibold
            case .body, .callout, .caption: .regular
            }
        }
    }

    /// The UI line-height multiple for chrome text (~1.3). Apply via
    /// `.lineSpacing(Typography.uiLineSpacing(for:))` where row height matters.
    public static let uiLineHeightMultiple: CGFloat = 1.3

    /// The extra `lineSpacing` (points) that yields `uiLineHeightMultiple`
    /// for a given font size.
    public static func uiLineSpacing(for size: CGFloat) -> CGFloat {
        size * (uiLineHeightMultiple - 1)
    }

    /// The default editor/code monospace point size.
    public static let monospaceSize: CGFloat = 13

    /// A SwiftUI `Font` for a scale style.
    public static func font(_ style: Style) -> Font {
        .system(size: style.size, weight: style.weight)
    }

    /// The monospace SwiftUI `Font` for code.
    public static func monospace(size: CGFloat = monospaceSize) -> Font {
        .system(size: size, design: .monospaced)
    }
}
