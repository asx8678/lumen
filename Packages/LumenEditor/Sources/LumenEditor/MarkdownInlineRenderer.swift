//
//  MarkdownInlineRenderer.swift
//  LumenEditor
//
//  Lowers a `[MarkdownInline]` run (from LumenCore's renderable model) into a
//  styled `AttributedString` for the reading view (P2.1.1). Pure and
//  UI-framework-light: it uses Foundation `inlinePresentationIntent` (bold,
//  italic, strikethrough, code) and the `.link` attribute, both of which
//  SwiftUI's `Text` honors — so the mapping is fully unit-testable without
//  standing up a view.
//

import Foundation
import LumenCore

/// Builds styled `AttributedString`s from inline Markdown runs.
public enum MarkdownInlineRenderer {
    /// Renders a run of inline nodes into a single styled `AttributedString`.
    ///
    /// - Parameter inlines: The inline children to render.
    /// - Returns: The combined attributed text, with emphasis/strong/
    ///   strikethrough/inline-code intents and link attributes applied.
    public static func attributedString(for inlines: [MarkdownInline]) -> AttributedString {
        render(inlines, intent: [], destination: nil)
    }

    /// The plain-text content of an inline run (markers stripped). Used for
    /// accessibility labels, table-cell sizing, and structural tests.
    public static func plainText(for inlines: [MarkdownInline]) -> String {
        inlines.map(plainText(for:)).joined()
    }

    // MARK: - Recursion

    private static func render(
        _ inlines: [MarkdownInline],
        intent: InlinePresentationIntent,
        destination: String?
    ) -> AttributedString {
        var result = AttributedString()
        for inline in inlines {
            result.append(fragment(for: inline, intent: intent, destination: destination))
        }
        return result
    }

    private static func fragment(
        for inline: MarkdownInline,
        intent: InlinePresentationIntent,
        destination: String?
    ) -> AttributedString {
        switch inline {
        case .text(let string):
            return styled(string, intent: intent, destination: destination)
        case .emphasis(let children):
            return render(children, intent: intent.union(.emphasized), destination: destination)
        case .strong(let children):
            return render(
                children, intent: intent.union(.stronglyEmphasized), destination: destination)
        case .strikethrough(let children):
            return render(
                children, intent: intent.union(.strikethrough), destination: destination)
        case .inlineCode(let code):
            return styled(code, intent: intent.union(.code), destination: destination)
        case .link(let dest, let children):
            return render(children, intent: intent, destination: dest ?? destination)
        case .image(_, let alt):
            // Inline images fall back to their alt text; standalone image blocks
            // are rendered as real images by the reading view.
            return styled(alt, intent: intent, destination: destination)
        case .lineBreak:
            return styled("\n", intent: intent, destination: destination)
        case .softBreak:
            return styled(" ", intent: intent, destination: destination)
        case .inlineHTML(let raw):
            return styled(raw, intent: intent.union(.code), destination: destination)
        }
    }

    private static func styled(
        _ string: String,
        intent: InlinePresentationIntent,
        destination: String?
    ) -> AttributedString {
        var fragment = AttributedString(string)
        if !intent.isEmpty {
            fragment.inlinePresentationIntent = intent
        }
        if let destination, let url = URL(string: destination) {
            fragment.link = url
        }
        return fragment
    }

    private static func plainText(for inline: MarkdownInline) -> String {
        switch inline {
        case .text(let string), .inlineCode(let string), .inlineHTML(let string):
            return string
        case .emphasis(let children), .strong(let children),
            .strikethrough(let children):
            return plainText(for: children)
        case .link(_, let children):
            return plainText(for: children)
        case .image(_, let alt):
            return alt
        case .lineBreak:
            return "\n"
        case .softBreak:
            return " "
        }
    }
}
