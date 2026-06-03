//
//  LivePreviewBlockDecorations.swift
//  LumenEditor
//
//  P2.2.1c (lumen-nmm.19) — pure, UI-free decision logic for *block-level*
//  Style-class live-preview decorations: blockquotes, lists, and fenced /
//  indented code blocks.
//
//  Like `LivePreviewDecorations` (inline markers), this type is deliberately
//  side-effect-free and headlessly testable. It maps a parsed tree-sitter node
//  set onto STRUCTURAL FACTS — region ranges, nesting depths, marker ranges,
//  bullet substitutions — and leaves all geometry (points, colors, drawing) to
//  the TextKit 2 *mechanism* (`LivePreviewBlockChromeProvider` + the content
//  storage delegate). Keeping the structure/geometry split here mirrors the
//  inline path and lets us unit-test the hard part (which characters, what
//  depth) without a live text view.
//
//  Scope per docs/phase2-live-preview-spec.md:
//  * Blockquote `> ` — persistent left accent bar + indent over the WHOLE
//    quote region (incl. multi-paragraph and nested `> >`); the `> ` markers
//    conceal per inactive line and reveal on the active line (the bar/indent
//    persist regardless).
//  * Lists — bullet markers `-`/`*`/`+` render as a persistent `•` glyph (even
//    on the active line); ordered `1.` markers are left as-is. Nesting and
//    hang-indent are expressed as depth.
//  * Fenced code ```` ``` ```` (and 4-space indented code) — a shaded box
//    region; the fences/info string stay visible (unlike reading view).
//
//  NOT handled here: W-class widgets (links/images/HR/tables/math) — those are
//  lumen-nmm.20/.21/.22. First-line frontmatter (`minus_metadata`) and setext
//  underlines are distinct node types, so they never appear as quotes/HRs in
//  the sets below — the spec's "don't misfire on `---`" gotcha is satisfied by
//  construction.
//

import Foundation

/// Pure decision logic for block-level live-preview decorations.
///
/// All ranges are UTF-16 code units (matching `NSString` / `NSTextStorage`).
public enum LivePreviewBlockDecorations {
    // MARK: - tree-sitter node taxonomy

    /// The whole blockquote region (one per `>`-prefixed block; nested quotes
    /// produce an inner region as well).
    private static let blockQuoteType = "block_quote"
    /// The leading `> ` token on a blockquote's first line.
    private static let blockQuoteMarkerType = "block_quote_marker"
    /// Continuation prefix tokens on a block's subsequent lines. For
    /// blockquotes these carry the `> ` of each continuation line; for lists /
    /// fenced code they carry indentation only — we keep just the `>`-bearing
    /// ones (see `blockquoteMarkerRanges`).
    private static let blockContinuationType = "block_continuation"

    /// Unordered list-marker node types (`- `, `* `, `+ `). Each is length 2
    /// (marker + the single following space).
    private static let bulletMarkerTypes: Set<String> = [
        "list_marker_minus", "list_marker_star", "list_marker_plus",
    ]
    /// Ordered list-marker node type (`1. `, `2. `, …). Left visible as-is.
    private static let orderedMarkerType = "list_marker_dot"
    /// The list-grouping node, used to compute nesting depth.
    private static let listType = "list"

    /// Fenced code region (```` ``` ````-delimited).
    private static let fencedCodeType = "fenced_code_block"
    /// 4-space indented code region.
    private static let indentedCodeType = "indented_code_block"

    /// The bullet glyph that replaces `-`/`*`/`+` markers in the display
    /// string (Obsidian-style). The trailing space preserves text spacing.
    public static let bulletGlyph = "•\u{00A0}"

    // MARK: - Blockquote

    /// A blockquote region and its nesting depth.
    public struct BlockquoteRegion: Equatable, Sendable {
        /// The full region range (covers every line of the quote).
        public let range: NSRange
        /// Nesting depth: 1 for `>`, 2 for `> >`, … Drives the number of
        /// accent bars and the indentation amount.
        public let depth: Int

        public init(range: NSRange, depth: Int) {
            self.range = range
            self.depth = depth
        }
    }

    /// Extracts blockquote regions with their nesting depth.
    ///
    /// Depth is the number of `block_quote` regions that contain a region's
    /// start offset (inclusive of itself), so an inner `> >` quote reports
    /// depth 2. Sorted by location.
    public static func blockquoteRegions(
        from nodes: [MarkdownSyntaxNode]
    ) -> [BlockquoteRegion] {
        let quotes = nodes.filter { $0.type == blockQuoteType }.map(\.range)
        var regions: [BlockquoteRegion] = []
        for quote in quotes {
            let depth = quotes.filter { contains($0, offset: quote.location) }.count
            regions.append(BlockquoteRegion(range: quote, depth: max(1, depth)))
        }
        return regions.sorted { $0.range.location < $1.range.location }
    }

    /// The number of blockquote accent bars to draw at a given character
    /// offset — i.e. the deepest quote nesting covering that offset (0 when the
    /// offset is outside any quote).
    public static func blockquoteDepth(
        at offset: Int,
        regions: [BlockquoteRegion]
    ) -> Int {
        regions.filter { contains($0.range, offset: offset) }.map(\.depth).max() ?? 0
    }

    /// The `> ` marker ranges (one per blockquote line) that obey the per-line
    /// reveal rule: concealed while their line is inactive, revealed (raw `>`
    /// shown) when the caret/selection touches the line. The accent bar and
    /// indent are driven separately by `blockquoteRegions`, so they persist on
    /// the active line — only the `>` text toggles.
    ///
    /// First-line markers come from `block_quote_marker`; continuation-line
    /// markers come from the `>`-bearing `block_continuation` nodes (the
    /// grammar emits the leading `> ` of every non-first quote line as a
    /// continuation token). Continuation tokens that carry only indentation
    /// (lists, fenced code) are excluded.
    public static func blockquoteMarkerRanges(
        from nodes: [MarkdownSyntaxNode],
        in text: NSString
    ) -> [NSRange] {
        let length = text.length
        var ranges: [NSRange] = []
        for node in nodes {
            guard node.range.location >= 0, NSMaxRange(node.range) <= length else { continue }
            switch node.type {
            case blockQuoteMarkerType:
                ranges.append(node.range)
            case blockContinuationType where containsGreaterThan(node.range, in: text):
                ranges.append(node.range)
            default:
                continue
            }
        }
        return normalize(ranges)
    }

    // MARK: - Lists

    /// A bullet-marker display substitution: the `-`/`*`/`+` (+ space) source
    /// range and the `•` glyph that replaces it. Bullets persist even on the
    /// active line, so these are NOT subject to the reveal rule.
    public struct BulletSubstitution: Equatable, Sendable {
        /// The source marker range (the `- ` / `* ` / `+ ` token, length 2).
        public let range: NSRange
        /// The replacement glyph (`•` + space).
        public let replacement: String
        /// List nesting depth (1 = top level), for hang-indent geometry.
        public let depth: Int

        public init(range: NSRange, replacement: String, depth: Int) {
            self.range = range
            self.replacement = replacement
            self.depth = depth
        }
    }

    /// Computes bullet-glyph substitutions for every unordered list marker.
    ///
    /// Depth is the number of `list` regions containing the marker (top level =
    /// 1), so nested bullets indent further. Ordered (`1.`) markers are not
    /// substituted — they keep their source text per the spec.
    public static func bulletSubstitutions(
        from nodes: [MarkdownSyntaxNode]
    ) -> [BulletSubstitution] {
        let lists = nodes.filter { $0.type == listType }.map(\.range)
        var subs: [BulletSubstitution] = []
        for node in nodes where bulletMarkerTypes.contains(node.type) {
            let depth = lists.filter { contains($0, offset: node.range.location) }.count
            subs.append(
                BulletSubstitution(
                    range: node.range, replacement: bulletGlyph, depth: max(1, depth)))
        }
        return subs.sorted { $0.range.location < $1.range.location }
    }

    /// The nesting depth of any list marker (ordered or unordered) at `offset`,
    /// or 0 if none — used to indent ordered items consistently with bullets.
    public static func listDepth(
        at offset: Int,
        from nodes: [MarkdownSyntaxNode]
    ) -> Int {
        let lists = nodes.filter { $0.type == listType }.map(\.range)
        return lists.filter { contains($0, offset: offset) }.count
    }

    // MARK: - Code blocks

    /// A code-block region to shade behind.
    public struct CodeBlockRegion: Equatable, Sendable {
        /// The full region range (fences + content for fenced; the whole
        /// indented run for indented code).
        public let range: NSRange
        /// `true` for ```` ``` ````-fenced blocks, `false` for 4-space indented.
        public let isFenced: Bool

        public init(range: NSRange, isFenced: Bool) {
            self.range = range
            self.isFenced = isFenced
        }
    }

    /// Extracts fenced and indented code-block regions to draw a shaded box
    /// behind. The fences / info string remain visible (the box is painted
    /// behind them); tree-sitter highlighting inside is untouched.
    public static func codeBlockRegions(
        from nodes: [MarkdownSyntaxNode]
    ) -> [CodeBlockRegion] {
        var regions: [CodeBlockRegion] = []
        for node in nodes {
            switch node.type {
            case fencedCodeType:
                regions.append(CodeBlockRegion(range: node.range, isFenced: true))
            case indentedCodeType:
                regions.append(CodeBlockRegion(range: node.range, isFenced: false))
            default:
                continue
            }
        }
        return regions.sorted { $0.range.location < $1.range.location }
    }

    // MARK: - Helpers

    /// Whether `range` contains `offset` (half-open: `[location, max)`).
    private static func contains(_ range: NSRange, offset: Int) -> Bool {
        offset >= range.location && offset < NSMaxRange(range)
    }

    /// Whether the (presumably continuation) range contains a `>` code unit —
    /// distinguishes blockquote continuation prefixes from pure indentation.
    private static func containsGreaterThan(_ range: NSRange, in text: NSString) -> Bool {
        for offset in range.location..<NSMaxRange(range) where text.character(at: offset) == 0x3E {
            return true
        }
        return false
    }

    /// Sorts ranges by location and removes exact duplicates.
    private static func normalize(_ ranges: [NSRange]) -> [NSRange] {
        var seen = Set<NSRange>()
        var unique: [NSRange] = []
        for range in ranges where seen.insert(range).inserted {
            unique.append(range)
        }
        return unique.sorted {
            $0.location != $1.location ? $0.location < $1.location : $0.length < $1.length
        }
    }
}
