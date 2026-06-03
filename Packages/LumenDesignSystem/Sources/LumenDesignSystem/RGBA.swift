//
//  RGBA.swift
//  LumenDesignSystem
//
//  A pure, Sendable color value (sRGB components) used to define palettes
//  without depending on AppKit/SwiftUI — which keeps token data unit-testable.
//  Conversions to `NSColor` / SwiftUI `Color` live here too.
//

import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

/// An sRGB color with components in `0...1`. Pure data, `Sendable`, `Equatable`.
public struct RGBA: Sendable, Equatable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Creates an `RGBA` from 8-bit channel values (0–255).
    public init(r: Int, g: Int, b: Int, a: Double = 1) {
        self.init(Double(r) / 255, Double(g) / 255, Double(b) / 255, a)
    }

    /// The SwiftUI representation.
    public var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    #if canImport(AppKit)
    /// The AppKit representation (sRGB).
    public var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
    #endif
}
