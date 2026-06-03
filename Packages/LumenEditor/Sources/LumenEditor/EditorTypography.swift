//
//  EditorTypography.swift
//  LumenEditor
//
//  The editor's adjustable typography (P1.13): font kind (monospace vs
//  proportional), size, readable max line width, and line spacing. A pure,
//  Codable value type — the @Observable store + UserDefaults persistence and
//  the menu controls live in the app; the per-vault `.lumen/` config is P1.19.
//
//  Base fonts/size come from the P1.17 `Typography` tokens. Resolution to an
//  `NSFont` + `NSParagraphStyle` lives here so the editor and highlighter share
//  one source of truth (the highlighter's base/bold/italic fonts derive from
//  the resolved base font, so typography composes with syntax highlighting).
//

import AppKit
import LumenDesignSystem

/// Adjustable editor typography settings.
public struct EditorTypography: Sendable, Equatable, Codable {
    /// The base font family.
    public enum FontKind: String, Sendable, Codable, CaseIterable {
        case monospace
        case proportional
    }

    /// Readable maximum content width presets.
    public enum LineWidth: String, Sendable, Codable, CaseIterable {
        case narrow
        case medium
        case wide
        case unlimited

        /// Content width in points, or `nil` for unlimited (full width).
        public var points: CGFloat? {
            switch self {
            case .narrow: 540
            case .medium: 680
            case .wide: 860
            case .unlimited: nil
            }
        }

        /// The next preset in a cycle (narrow → medium → wide → unlimited → …).
        public var next: LineWidth {
            let all = LineWidth.allCases
            let index = all.firstIndex(of: self) ?? 0
            return all[(index + 1) % all.count]
        }
    }

    // MARK: - Clamps

    /// Smallest allowed font size.
    public static let minFontSize: CGFloat = 9
    /// Largest allowed font size.
    public static let maxFontSize: CGFloat = 32
    /// Smallest allowed line-height multiple.
    public static let minLineSpacing: CGFloat = 1.0
    /// Largest allowed line-height multiple.
    public static let maxLineSpacing: CGFloat = 2.5

    // MARK: - Stored

    public var fontKind: FontKind
    /// Base point size (clamped to `minFontSize...maxFontSize`).
    public var fontSize: CGFloat
    public var lineWidth: LineWidth
    /// Line-height multiple (clamped to `minLineSpacing...maxLineSpacing`).
    public var lineSpacing: CGFloat

    public init(
        fontKind: FontKind = .monospace,
        fontSize: CGFloat = Typography.monospaceSize,
        lineWidth: LineWidth = .medium,
        lineSpacing: CGFloat = 1.3
    ) {
        self.fontKind = fontKind
        self.fontSize = Self.clampSize(fontSize)
        self.lineWidth = lineWidth
        self.lineSpacing = Self.clampSpacing(lineSpacing)
    }

    /// The default typography (monospace, token size, medium width).
    public static let `default` = EditorTypography()

    /// Decodes and clamps (so persisted/edited values can't escape bounds).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            fontKind: try c.decode(FontKind.self, forKey: .fontKind),
            fontSize: try c.decode(CGFloat.self, forKey: .fontSize),
            lineWidth: try c.decode(LineWidth.self, forKey: .lineWidth),
            lineSpacing: try c.decode(CGFloat.self, forKey: .lineSpacing))
    }

    // MARK: - Resolution

    /// The resolved `NSFont` for the chosen kind + size.
    public func resolvedFont() -> NSFont {
        switch fontKind {
        case .monospace:
            .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        case .proportional:
            .systemFont(ofSize: fontSize)
        }
    }

    /// The resolved paragraph style applying the line-spacing multiple.
    public func resolvedParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineSpacing
        return style
    }

    // MARK: - Adjusters (return clamped copies)

    /// Toggles between monospace and proportional.
    public func togglingFontKind() -> EditorTypography {
        var copy = self
        copy.fontKind = (fontKind == .monospace) ? .proportional : .monospace
        return copy
    }

    /// A copy with the font size changed by `delta` (clamped).
    public func adjustingFontSize(by delta: CGFloat) -> EditorTypography {
        var copy = self
        copy.fontSize = Self.clampSize(fontSize + delta)
        return copy
    }

    /// A copy with the font size reset to the token default.
    public func resettingFontSize() -> EditorTypography {
        var copy = self
        copy.fontSize = Typography.monospaceSize
        return copy
    }

    /// A copy advanced to the next line-width preset.
    public func cyclingLineWidth() -> EditorTypography {
        var copy = self
        copy.lineWidth = lineWidth.next
        return copy
    }

    // MARK: - Helpers

    static func clampSize(_ value: CGFloat) -> CGFloat {
        min(maxFontSize, max(minFontSize, value))
    }

    static func clampSpacing(_ value: CGFloat) -> CGFloat {
        min(maxLineSpacing, max(minLineSpacing, value))
    }
}
