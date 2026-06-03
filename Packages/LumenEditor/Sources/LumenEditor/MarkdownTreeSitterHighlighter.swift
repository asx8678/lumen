//
//  MarkdownTreeSitterHighlighter.swift
//  LumenEditor
//
//  P2.0.2 — Tree-sitter-driven Markdown syntax highlighter.
//
//  Replaces the Phase-1 regex / line-based highlighter (`MarkdownHighlighter`).
//  Instead of re-scanning text with regular expressions, it maps the typed
//  nodes produced by `MarkdownTreeSitterParser` (block + inline grammars) onto
//  the existing `MarkdownHighlightTheme` styles. This is both more accurate
//  (nested emphasis, multi-line fenced code, links, headings incl. markers)
//  and incremental — nodes come from the parser's persistent, incrementally
//  reparsed tree.
//
//  Mapping runs on the main actor (it touches `NSColor` / `NSFont` via the
//  theme), but the *parsing* and node query happen on the parser actor, off
//  the keystroke hot path.
//

import AppKit

/// Maps tree-sitter Markdown parse nodes onto highlight attributes.
///
/// The highlighter is stateless: callers pass the nodes overlapping a range
/// (typically the visible viewport or a changed paragraph) plus the theme, and
/// receive styled spans to overlay on the text storage.
public struct MarkdownTreeSitterHighlighter {
    public init() {}

    /// A styled span: a character range plus the attributes to apply.
    public struct StyledRange {
        public let range: NSRange
        public let attributes: [NSAttributedString.Key: Any]

        public init(range: NSRange, attributes: [NSAttributedString.Key: Any]) {
            self.range = range
            self.attributes = attributes
        }
    }

    // MARK: - Public API

    /// Computes highlighting spans for the given parse nodes.
    ///
    /// Nodes are expected in document order with block nodes preceding the
    /// inline nodes discovered within them (the order `MarkdownTreeSitterParser`
    /// produces). Spans are emitted in the same order, so when the editor
    /// applies them sequentially the more specific *inline* tokens (emphasis,
    /// links, code spans) correctly overlay the surrounding *block* styling —
    /// e.g. bold inside a list item, or emphasis inside a heading.
    ///
    /// - Parameters:
    ///   - nodes: Parse nodes overlapping the range being styled.
    ///   - theme: The colors/fonts to apply.
    /// - Returns: Styled spans, in application order.
    public func styledRanges(
        for nodes: [MarkdownSyntaxNode],
        theme: MarkdownHighlightTheme
    ) -> [StyledRange] {
        var spans: [StyledRange] = []
        spans.reserveCapacity(nodes.count)
        for node in nodes {
            if let attributes = attributes(for: node.type, theme: theme) {
                spans.append(StyledRange(range: node.range, attributes: attributes))
            }
        }
        return spans
    }

    // MARK: - Node-type → style mapping

    /// Returns the attributes for a tree-sitter node type, or `nil` if the type
    /// carries no highlighting (so the body baseline shows through).
    private func attributes(
        for type: String,
        theme: MarkdownHighlightTheme
    ) -> [NSAttributedString.Key: Any]? {
        switch type {
        // MARK: Headings
        case "atx_heading", "setext_heading":
            return [.foregroundColor: theme.headingColor, .font: theme.boldFont]

        // MARK: Fenced / indented code
        case "fenced_code_block", "indented_code_block", "code_fence_content":
            return [.foregroundColor: theme.codeColor, .font: theme.baseFont]
        // Fence delimiters + the info string (```swift) are dimmer than content.
        case "fenced_code_block_delimiter", "info_string", "language":
            return [.foregroundColor: theme.fenceColor, .font: theme.baseFont]

        // MARK: Blockquotes
        case "block_quote":
            return [.foregroundColor: theme.quoteColor]
        case "block_quote_marker":
            return [.foregroundColor: theme.quoteColor, .font: theme.boldFont]

        // MARK: List markers
        case "list_marker_minus", "list_marker_star", "list_marker_plus",
            "list_marker_dot", "list_marker_parenthesis":
            return [.foregroundColor: theme.listMarkerColor, .font: theme.boldFont]

        // MARK: Inline emphasis
        case "strong_emphasis":
            return [.foregroundColor: theme.emphasisColor, .font: theme.boldFont]
        case "emphasis":
            return [.foregroundColor: theme.emphasisColor, .font: theme.italicFont]
        // GFM strikethrough (`~~x~~`): the grammar tags it `strikethrough`.
        case "strikethrough":
            return [
                .foregroundColor: theme.strikethroughColor,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: theme.strikethroughColor,
            ]

        // MARK: Inline code
        case "code_span":
            return [.foregroundColor: theme.codeColor, .font: theme.baseFont]

        // MARK: Links / images
        case "link_text", "image_description":
            return [
                .foregroundColor: theme.linkTextColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ]
        case "link_destination", "link_label", "link_title", "uri_autolink":
            return [.foregroundColor: theme.linkURLColor]

        default:
            return nil
        }
    }
}
