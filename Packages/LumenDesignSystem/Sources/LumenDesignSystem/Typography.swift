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
    /// A named step in the type scale.
    public enum Style: Sendable, CaseIterable {
        case largeTitle
        case title
        case headline
        case body
        case callout
        case caption

        /// Point size for the style.
        public var size: CGFloat {
            switch self {
            case .largeTitle: 26
            case .title: 20
            case .headline: 15
            case .body: 13
            case .callout: 12
            case .caption: 11
            }
        }

        /// Font weight for the style.
        public var weight: Font.Weight {
            switch self {
            case .largeTitle, .title: .semibold
            case .headline: .semibold
            case .body, .callout, .caption: .regular
            }
        }
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
