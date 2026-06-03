//
//  LivePreviewWidgetDecorations.swift
//  LumenEditor
//
//  P2.2.1d (lumen-nmm.20) — pure, UI-free decision logic for *Widget-class*
//  (W) live-preview decorations.
//
//  Where Style-class decorations (`LivePreviewDecorations`) only conceal short
//  marker tokens and keep the same characters, a Widget REPLACES a source range
//  with a rendering whose *content/structure* differs from the raw Markdown:
//
//  * Link `[t](u)`          → display `t`, link-styled.
//  * Wikilink `[[N|a]]` etc → display the alias / heading / last path segment.
//  * Inline image `![…](…)` / `![[…]]` → the rendered image (or a placeholder).
//  * Horizontal rule `---`/`***`/`___` (standalone) → an `<hr>` rule.
//
//  Per the spec's reveal rule, a Widget reverts FULLY to its raw source on the
//  active line (caret/selection intersecting its logical line) — unlike an S
//  decoration which merely un-hides its markers. This type owns ONLY the
//  decision of WHICH source ranges are widgets, what each renders as, and
//  whether a given selection reverts it. All geometry / drawing lives in the
//  TextKit 2 mechanism (`LivePreviewConcealmentController` widget substitutions
//  + `LivePreviewWidgetRendering`).
//
//  Like the other live-preview deciders it is side-effect-free and headlessly
//  testable. All ranges are UTF-16 code units (matching `NSString`).
//
//  Grammar mapping (confirmed against the bundled tree-sitter-markdown):
//  * `inline_link` (with child `link_text` + `link_destination`) → link.
//  * `image` (with `image_description` + `link_destination`)      → image.
//  * `thematic_break`                                             → HR.
//    (Frontmatter `minus_metadata` and `setext_h?_underline` are DISTINCT
//    node types, so first-line `---…---` and setext `---` are never HRs here —
//    the spec's gotcha #6 is satisfied by construction.)
//  Wikilinks `[[…]]` / embeds `![[…]]` are an Obsidian extension the grammar
//  does NOT model (it sees a bare `shortcut_link`), so — like `==highlight==` —
//  they are recovered by a balanced text scan.
//

import Foundation

/// Pure decision logic for Widget-class live-preview decorations.
public enum LivePreviewWidgetDecorations {
    // MARK: - Model

    /// What a widget renders as (drives the mechanism's substitution).
    public enum Kind: Equatable, Sendable {
        /// A Markdown inline link `[t](u)`; `url` is the destination.
        case link(url: String)
        /// A wikilink `[[target]]` / `[[target|alias]]` / `[[target#h]]`;
        /// `target` is the full inner text (everything between `[[` and `]]`).
        case wikilink(target: String)
        /// An image: Markdown `![alt](u)` or an embed `![[file]]`. `isEmbed`
        /// distinguishes the wiki-embed form (which the mechanism may persist).
        case image(url: String, isEmbed: Bool)
        /// A standalone horizontal rule (`---` / `***` / `___`).
        case horizontalRule
    }

    /// A resolved widget: the raw source it replaces, what it renders as, and
    /// the display label (link text / alias / filename — empty for rules).
    public struct Widget: Equatable, Sendable {
        /// The source range the widget replaces (UTF-16). Reverting reveals it.
        public let sourceRange: NSRange
        /// What this widget renders as.
        public let kind: Kind
        /// The text shown in place of the source (empty for `horizontalRule`).
        public let displayLabel: String

        public init(sourceRange: NSRange, kind: Kind, displayLabel: String) {
            self.sourceRange = sourceRange
            self.kind = kind
            self.displayLabel = displayLabel
        }
    }

    // MARK: - tree-sitter node taxonomy

    private static let linkType = "inline_link"
    private static let imageType = "image"
    private static let thematicBreakType = "thematic_break"
    private static let linkTextType = "link_text"
    private static let linkDestinationType = "link_destination"
    private static let imageDescriptionType = "image_description"

    // MARK: - Extraction

    /// Extracts every widget in document order from a parsed node set + text.
    ///
    /// Grammar-driven widgets (links, images, HRs) are read from `nodes`;
    /// wikilinks and wiki-embeds are recovered by scanning `text` for balanced
    /// `[[…]]` / `![[…]]`. Grammar `image` nodes that are actually embeds
    /// (`![[…]]`) are skipped so the scan owns them (avoids double-counting).
    ///
    /// - Parameters:
    ///   - nodes: Parse nodes (typically the viewport set).
    ///   - text: The document text.
    /// - Returns: Widgets sorted by source location, de-duplicated.
    public static func widgets(
        from nodes: [MarkdownSyntaxNode],
        in text: NSString
    ) -> [Widget] {
        let length = text.length
        var widgets: [Widget] = []

        for node in nodes {
            guard node.range.location >= 0, NSMaxRange(node.range) <= length else { continue }
            switch node.type {
            case linkType:
                if let widget = linkWidget(for: node, nodes: nodes, in: text) {
                    widgets.append(widget)
                }
            case imageType:
                // Embeds (`![[…]]`) are handled by the wikilink scan below.
                if text.substring(with: node.range).hasPrefix("![[") { continue }
                if let widget = imageWidget(for: node, nodes: nodes, in: text) {
                    widgets.append(widget)
                }
            case thematicBreakType:
                widgets.append(
                    Widget(
                        sourceRange: trimTrailingNewline(node.range, in: text),
                        kind: .horizontalRule,
                        displayLabel: ""))
            default:
                continue
            }
        }

        widgets.append(contentsOf: wikilinkWidgets(in: text))
        return normalize(widgets)
    }

    /// The source ranges of `widgets`, for caret-atomicity (the caret must step
    /// over a rendered widget's source as one unit). Sorted by location.
    public static func sourceRanges(of widgets: [Widget]) -> [NSRange] {
        widgets.map(\.sourceRange).sorted { $0.location < $1.location }
    }

    // MARK: - Active-line revert decision

    /// Splits widgets into those that should *render* (their line is inactive)
    /// versus *revert* to raw source (their line is active), using the same
    /// per-logical-line reveal rule as the S-class path: a caret/selection
    /// anywhere on a widget's line(s) reverts every widget on that line.
    ///
    /// A widget that spans multiple lines (a multi-line selection over its
    /// source, or a block embed) reverts if ANY of its lines is active.
    ///
    /// - Parameters:
    ///   - text: The document text.
    ///   - selections: Current selection ranges (caret = zero length).
    ///   - widgets: Widgets to partition.
    /// - Returns: `rendered` and `reverted` widget arrays (document order).
    public static func resolve(
        in text: NSString,
        selections: [NSRange],
        widgets: [Widget]
    ) -> (rendered: [Widget], reverted: [Widget]) {
        let activeLines = LivePreviewDecorations.activeLineRanges(
            in: text, selections: selections)
        var rendered: [Widget] = []
        var reverted: [Widget] = []
        for widget in widgets {
            let widgetLines = text.lineRange(for: widget.sourceRange)
            let isActive = activeLines.contains { intersects($0, widgetLines) }
            if isActive {
                reverted.append(widget)
            } else {
                rendered.append(widget)
            }
        }
        return (rendered, reverted)
    }

    // MARK: - Link / image child resolution

    private static func linkWidget(
        for node: MarkdownSyntaxNode,
        nodes: [MarkdownSyntaxNode],
        in text: NSString
    ) -> Widget? {
        let label = childText(linkTextType, within: node.range, nodes: nodes, in: text)
        let url = childText(linkDestinationType, within: node.range, nodes: nodes, in: text)
        guard let label, !label.isEmpty else { return nil }
        return Widget(
            sourceRange: node.range,
            kind: .link(url: url ?? ""),
            displayLabel: label)
    }

    private static func imageWidget(
        for node: MarkdownSyntaxNode,
        nodes: [MarkdownSyntaxNode],
        in text: NSString
    ) -> Widget? {
        let alt = childText(imageDescriptionType, within: node.range, nodes: nodes, in: text) ?? ""
        let url = childText(linkDestinationType, within: node.range, nodes: nodes, in: text) ?? ""
        let label = alt.isEmpty ? lastPathSegment(of: url) : alt
        return Widget(
            sourceRange: node.range,
            kind: .image(url: url, isEmbed: false),
            displayLabel: label)
    }

    /// The text of the first `type` child node fully inside `parent`.
    private static func childText(
        _ type: String,
        within parent: NSRange,
        nodes: [MarkdownSyntaxNode],
        in text: NSString
    ) -> String? {
        for node in nodes
        where node.type == type
            && node.range.location >= parent.location
            && NSMaxRange(node.range) <= NSMaxRange(parent)
        {
            return text.substring(with: node.range)
        }
        return nil
    }

    // MARK: - Wikilink / embed scanning (no grammar support)

    /// Scans `text` for balanced wikilinks `[[…]]` and embeds `![[…]]`.
    ///
    /// Honors the spec's marker gotchas: a span never crosses a newline, an
    /// unbalanced `[[` (while typing) stays raw, an escaped `\[` does not open
    /// a span, and the inner text must be non-empty.
    public static func wikilinkWidgets(in text: NSString) -> [Widget] {
        let length = text.length
        guard length >= 4 else { return [] }
        var widgets: [Widget] = []
        var i = 0
        while i < length - 1 {
            guard isOpen(at: i, in: text) else {
                i += 1
                continue
            }
            // Find the closing `]]` on the same logical line.
            var j = i + 2
            var close = -1
            while j < length - 1 {
                let unit = text.character(at: j)
                if unit == 0x0A { break }  // newline ends the inline scope
                if text.character(at: j) == 0x5D, text.character(at: j + 1) == 0x5D {
                    close = j
                    break
                }
                j += 1
            }
            guard close > i + 2 else {
                i += 1
                continue
            }
            let isEmbed = i > 0 && text.character(at: i - 1) == 0x21  // `!`
            let start = isEmbed ? i - 1 : i
            let inner = text.substring(with: NSRange(location: i + 2, length: close - (i + 2)))
            let source = NSRange(location: start, length: (close + 2) - start)
            if isEmbed {
                widgets.append(
                    Widget(
                        sourceRange: source,
                        kind: .image(url: inner, isEmbed: true),
                        displayLabel: lastPathSegment(of: inner)))
            } else {
                widgets.append(
                    Widget(
                        sourceRange: source,
                        kind: .wikilink(target: inner),
                        displayLabel: wikilinkLabel(for: inner)))
            }
            i = close + 2
        }
        return widgets
    }

    /// The label a wikilink renders: alias if present, else the heading/block
    /// reference if present, else the last path segment of the target.
    public static func wikilinkLabel(for inner: String) -> String {
        if let pipe = inner.firstIndex(of: "|") {
            let alias = String(inner[inner.index(after: pipe)...])
            if !alias.isEmpty { return alias }
        }
        let target = inner.split(separator: "|", maxSplits: 1).first.map(String.init) ?? inner
        if let hash = target.firstIndex(of: "#") {
            var heading = String(target[target.index(after: hash)...])
            if heading.hasPrefix("^") { heading.removeFirst() }  // block ref `#^id`
            if !heading.isEmpty { return heading }
        }
        let path = target.split(separator: "#", maxSplits: 1).first.map(String.init) ?? target
        return lastPathSegment(of: path)
    }

    /// Whether a `[[` opens at `index` (two `[` with the first not escaped).
    private static func isOpen(at index: Int, in text: NSString) -> Bool {
        guard index + 1 < text.length else { return false }
        guard text.character(at: index) == 0x5B, text.character(at: index + 1) == 0x5B else {
            return false
        }
        var backslashes = 0
        var k = index - 1
        while k >= 0, text.character(at: k) == 0x5C {
            backslashes += 1
            k -= 1
        }
        return backslashes % 2 == 0
    }

    // MARK: - Helpers

    /// The last `/`-separated segment of a path-like string (its own value when
    /// there is no separator). Used for image filenames and wikilink targets.
    static func lastPathSegment(of path: String) -> String {
        let trimmed = path.split(separator: "/").last.map(String.init) ?? path
        return trimmed
    }

    /// Drops a single trailing newline from a range (so an HR widget covers the
    /// `---` glyphs, not the line terminator that ends its paragraph).
    private static func trimTrailingNewline(_ range: NSRange, in text: NSString) -> NSRange {
        var length = range.length
        while length > 0,
            text.character(at: range.location + length - 1) == 0x0A
                || text.character(at: range.location + length - 1) == 0x0D
        {
            length -= 1
        }
        return NSRange(location: range.location, length: length)
    }

    private static func intersects(_ a: NSRange, _ b: NSRange) -> Bool {
        let start = max(a.location, b.location)
        let end = min(NSMaxRange(a), NSMaxRange(b))
        return start < end
    }

    private static func normalize(_ widgets: [Widget]) -> [Widget] {
        var seen = Set<NSRange>()
        var unique: [Widget] = []
        for widget in widgets.sorted(by: { $0.sourceRange.location < $1.sourceRange.location })
        where seen.insert(widget.sourceRange).inserted {
            unique.append(widget)
        }
        return unique
    }
}
