//
//  MarkdownHighlightTheme+DesignSystem.swift
//  LumenEditor
//
//  Fills the P1.12 highlighter seam from P1.17 design tokens. LumenEditor
//  depends on LumenDesignSystem (the leaf, dependency-free token package), so
//  the tokens→highlight-theme mapping lives here, next to the highlighter, and
//  is reusable by anything that hosts the editor.
//

import AppKit
import LumenDesignSystem

extension MarkdownHighlightTheme {
    /// Builds a highlight theme from a design-system ``Palette``.
    ///
    /// Markdown syntax colors come from the palette's `md*` tokens, so they
    /// respond to the active appearance the same way the rest of the UI does.
    /// - Parameters:
    ///   - palette: The resolved color palette.
    ///   - baseFont: The monospace base font (typography is P1.13's concern).
    public init(
        palette: Palette,
        baseFont: NSFont = .monospacedSystemFont(
            ofSize: Typography.monospaceSize, weight: .regular),
        paragraphStyle: NSParagraphStyle = .default
    ) {
        self.init(
            baseFont: baseFont,
            bodyColor: palette.textPrimary.nsColor,
            headingColor: palette.mdHeading.nsColor,
            codeColor: palette.mdCode.nsColor,
            fenceColor: palette.mdFence.nsColor,
            linkTextColor: palette.mdLinkText.nsColor,
            linkURLColor: palette.mdLinkURL.nsColor,
            listMarkerColor: palette.mdListMarker.nsColor,
            quoteColor: palette.mdQuote.nsColor,
            emphasisColor: palette.mdEmphasis.nsColor,
            codeBlockBackgroundColor: palette.surfaceBackground.nsColor,
            paragraphStyle: paragraphStyle
        )
    }

    /// Builds a highlight theme from a design-system ``Theme``.
    public init(theme: Theme) {
        self.init(palette: theme.palette)
    }

    /// Builds a highlight theme from a ``Theme`` + editor ``EditorTypography``
    /// (P1.13): the base font + line spacing come from typography so the
    /// highlighter's font/paragraph baseline matches the editor exactly.
    public init(theme: Theme, typography: EditorTypography) {
        self.init(
            palette: theme.palette,
            baseFont: typography.resolvedFont(),
            paragraphStyle: typography.resolvedParagraphStyle())
    }
}
