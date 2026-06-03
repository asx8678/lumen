//
//  LivePreviewWidgetRendering.swift
//  LumenEditor
//
//  P2.2.1d (lumen-nmm.20) — the small AppKit bridge that lowers a pure
//  `LivePreviewWidgetDecorations.Widget` into the styled `NSAttributedString`
//  the concealment delegate substitutes for the widget's raw source.
//
//  Kept separate from the pure decision logic so the decider stays headlessly
//  testable; this file owns only colors/fonts/attachments. Geometry stays
//  correct because the substituted string is laid out by TextKit 2 exactly like
//  any other display run (the same mechanism used for concealed markers and
//  bullet glyphs).
//
//  Per-element:
//  * Link / wikilink → the display label, link-styled (link color + underline)
//    with a `.link` attribute so the text view's `clickedOnLink` hook can open
//    it; wikilinks carry a `lumen-wikilink:` URL the host resolves to a note.
//  * Image          → a link-styled placeholder showing the filename/alt (the
//    actual pixel load needs the note's base URL plumbed into the editor — see
//    the follow-up filed with this task); the widget still reverts on the
//    active line, matching the spec.
//  * Horizontal rule → an `NSTextAttachment` that draws a thin full-width rule.
//

import AppKit

/// Builds the styled display string for a Widget-class live-preview decoration.
enum LivePreviewWidgetRendering {
    /// The URL scheme used to encode an unresolved wikilink target so the host
    /// app can intercept it in `textView(_:clickedOnLink:at:)` and open a note.
    static let wikilinkScheme = "lumen-wikilink"

    /// Lowers `widget` into its display attributed string.
    ///
    /// - Parameters:
    ///   - widget: The resolved widget to render.
    ///   - font: The editor's base font (keeps the run on the text baseline).
    ///   - linkColor: Link foreground color.
    ///   - ruleColor: Color of the horizontal-rule glyph.
    ///   - placeholderColor: Color for the image placeholder label.
    ///   - width: Container width, so a rule spans the readable column.
    ///   - image: The loaded image pixels for an `.image` widget, when
    ///     available; `nil` falls back to the link-styled placeholder.
    ///   - maxImageWidth: The maximum display width for a rendered image.
    static func attributedString(
        for widget: LivePreviewWidgetDecorations.Widget,
        font: NSFont,
        linkColor: NSColor,
        ruleColor: NSColor,
        placeholderColor: NSColor,
        width: CGFloat,
        image: NSImage? = nil,
        maxImageWidth: CGFloat = 480
    ) -> NSAttributedString {
        switch widget.kind {
        case .link(let url):
            return linkString(
                label: widget.displayLabel, destination: url, font: font, color: linkColor)
        case .wikilink(let target):
            let destination = "\(wikilinkScheme)://\(percentEncoded(target))"
            return linkString(
                label: widget.displayLabel, destination: destination, font: font, color: linkColor)
        case .image:
            if let image {
                return imageString(image, maxWidth: min(maxImageWidth, max(width - 8, 32)))
            }
            return placeholderString(
                label: widget.displayLabel.isEmpty ? "image" : widget.displayLabel,
                font: font, color: placeholderColor)
        case .horizontalRule:
            return ruleString(font: font, color: ruleColor, width: width)
        }
    }

    // MARK: - Builders

    private static func linkString(
        label: String,
        destination: String,
        font: NSFont,
        color: NSColor
    ) -> NSAttributedString {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        if let url = URL(string: destination) {
            attrs[.link] = url
            attrs[.toolTip] = destination
        }
        return NSAttributedString(string: label, attributes: attrs)
    }

    private static func placeholderString(
        label: String,
        font: NSFont,
        color: NSColor
    ) -> NSAttributedString {
        let italic = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        return NSAttributedString(
            string: "\u{1F5BC} \(label)",
            attributes: [.font: italic, .foregroundColor: color])
    }

    /// An inline image attachment, scaled to fit `maxWidth` while preserving
    /// aspect ratio (never upscaled past the source's natural size).
    private static func imageString(_ image: NSImage, maxWidth: CGFloat) -> NSAttributedString {
        let natural = image.size
        let attachment = NSTextAttachment()
        attachment.image = image
        if natural.width > 0, natural.height > 0 {
            let scale = min(1, maxWidth / natural.width)
            attachment.bounds = NSRect(
                x: 0, y: 0,
                width: natural.width * scale,
                height: natural.height * scale)
        }
        return NSAttributedString(attachment: attachment)
    }

    private static func ruleString(
        font: NSFont, color: NSColor, width: CGFloat
    ) -> NSAttributedString {
        let attachment = NSTextAttachment()
        let ruleWidth = max(width - 8, 32)
        let height = max(font.pointSize, 12)
        let image = NSImage(size: NSSize(width: ruleWidth, height: height))
        image.lockFocus()
        color.setFill()
        let lineHeight: CGFloat = 1
        NSRect(x: 0, y: (height - lineHeight) / 2, width: ruleWidth, height: lineHeight).fill()
        image.unlockFocus()
        attachment.image = image
        attachment.bounds = NSRect(x: 0, y: 0, width: ruleWidth, height: height)
        return NSAttributedString(attachment: attachment)
    }

    private static func percentEncoded(_ target: String) -> String {
        target.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? target
    }
}
