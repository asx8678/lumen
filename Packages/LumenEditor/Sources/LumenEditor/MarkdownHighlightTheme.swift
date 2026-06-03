//
//  MarkdownHighlightTheme.swift
//  LumenEditor
//
//  Injectable style configuration for the lightweight Markdown highlighter
//  (P1.12). The real design-token / theming engine is P1.17 — this struct is
//  the seam through which it will inject colors/weights later, without
//  rewriting the highlighter itself.
//

import AppKit

/// Colors and fonts used by the Markdown syntax highlighter.
///
/// Values are dynamic system colors so the editor survives light/dark mode.
/// P1.17 (design tokens) can build one of these from design tokens and pass it
/// in; the highlighter has no other knowledge of styling.
public struct MarkdownHighlightTheme {
    /// Base font for ordinary body text.
    public var baseFont: NSFont
    /// Foreground color for ordinary body text.
    public var bodyColor: NSColor

    /// Color for heading text (`#` … `######`).
    public var headingColor: NSColor
    /// Color for inline and fenced code.
    public var codeColor: NSColor
    /// Color for code-fence lines (```).
    public var fenceColor: NSColor
    /// Color for the link's display text.
    public var linkTextColor: NSColor
    /// Color for the link's URL.
    public var linkURLColor: NSColor
    /// Color for list markers (`-`, `*`, `+`, `1.`).
    public var listMarkerColor: NSColor
    /// Color for blockquote markers (`>`).
    public var quoteColor: NSColor
    /// Color for emphasis (bold / italic) runs.
    public var emphasisColor: NSColor

    public init(
        baseFont: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular),
        bodyColor: NSColor = .labelColor,
        headingColor: NSColor = .systemBlue,
        codeColor: NSColor = .systemPink,
        fenceColor: NSColor = .tertiaryLabelColor,
        linkTextColor: NSColor = .linkColor,
        linkURLColor: NSColor = .systemTeal,
        listMarkerColor: NSColor = .systemOrange,
        quoteColor: NSColor = .secondaryLabelColor,
        emphasisColor: NSColor = .labelColor
    ) {
        self.baseFont = baseFont
        self.bodyColor = bodyColor
        self.headingColor = headingColor
        self.codeColor = codeColor
        self.fenceColor = fenceColor
        self.linkTextColor = linkTextColor
        self.linkURLColor = linkURLColor
        self.listMarkerColor = listMarkerColor
        self.quoteColor = quoteColor
        self.emphasisColor = emphasisColor
    }

    /// The default ad-hoc theme used until P1.17 injects design tokens.
    @MainActor public static let `default` = MarkdownHighlightTheme()

    // MARK: - Derived fonts

    /// The bold variant of `baseFont`.
    var boldFont: NSFont {
        NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
    }

    /// The italic variant of `baseFont`.
    var italicFont: NSFont {
        NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
    }
}
