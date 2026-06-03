//
//  LivePreviewDecorations.swift
//  LumenEditor
//
//  P2.2.1 (lumen-nmm.5) — SPIKE: pure active-line reveal logic for inline
//  live preview.
//
//  This file is deliberately UI-free and side-effect-free: it maps a parsed
//  node set + the current selection onto the marker ranges that should be
//  *concealed* (raw source hidden, content styled) versus *revealed* (raw
//  markers shown because the caret/selection touches their logical line).
//
//  It is the de-risked, headlessly-testable core of the live-preview feature.
//  The TextKit 2 concealment *mechanism* that consumes these ranges lives in
//  `LivePreviewConcealmentController`; this type owns only the decision of
//  WHICH ranges to conceal, per the spec's per-logical-line reveal rule.
//
//  SCOPE (spike): Style-class inline elements only — headings (`#`), bold
//  (`**`), italic (`*` / `_`), inline code (`` ` ``). Widget-class elements
//  (links, images, HR, tables), lists and blockquotes are intentionally
//  EXCLUDED here; see docs/phase2-live-preview-spec.md.
//

import Foundation

/// Pure decision logic for inline live-preview marker concealment.
///
/// All ranges are UTF-16 code units (matching `NSString` / `NSTextStorage`),
/// so results apply directly to the editor's content storage.
public enum LivePreviewDecorations {
    // MARK: - Marker node taxonomy (Style-class, spike scope)

    /// tree-sitter node types whose ranges are *concealable markers* for the
    /// Style-class spike. Each is a short delimiter token that the rendered
    /// form drops while keeping the surrounding text styled.
    ///
    /// - `atx_h1_marker` … `atx_h6_marker`: the leading `#` run of an ATX
    ///   heading (the following space is folded in by `markerRanges(from:in:)`).
    /// - `emphasis_delimiter`: a single `*` or `_` delimiter; bold (`**`)
    ///   surfaces as two adjacent delimiters which fold into one concealed run.
    ///   The Markdown grammar also tags strikethrough `~` delimiters
    ///   (`~~x~~`, GFM) as `emphasis_delimiter`, so strikethrough markers are
    ///   concealed by the same rule as bold/italic — no extra node type needed.
    /// - `code_span_delimiter`: a `` ` `` run bounding an inline `code_span`.
    public static let markerNodeTypes: Set<String> = [
        "atx_h1_marker", "atx_h2_marker", "atx_h3_marker",
        "atx_h4_marker", "atx_h5_marker", "atx_h6_marker",
        "emphasis_delimiter", "code_span_delimiter",
    ]

    /// Heading markers additionally swallow the run of spaces that separates
    /// `#` from the heading text, so concealment hides `# ` (not just `#`).
    private static let headingMarkerTypes: Set<String> = [
        "atx_h1_marker", "atx_h2_marker", "atx_h3_marker",
        "atx_h4_marker", "atx_h5_marker", "atx_h6_marker",
    ]

    // MARK: - Marker extraction

    /// Extracts concealable marker ranges from a parsed node set.
    ///
    /// Heading markers are extended to include trailing ASCII spaces so the
    /// concealed token is `# ` rather than a bare `#` (which would leave an
    /// orphaned leading space). Ranges are returned sorted by location with
    /// any duplicates removed.
    ///
    /// - Parameters:
    ///   - nodes: Parse nodes (typically the viewport set from the parser).
    ///   - text: The document text, used to fold trailing heading whitespace.
    /// - Returns: Sorted, de-duplicated marker ranges in UTF-16 coordinates.
    public static func markerRanges(
        from nodes: [MarkdownSyntaxNode],
        in text: NSString
    ) -> [NSRange] {
        var ranges: [NSRange] = []
        let length = text.length
        for node in nodes where markerNodeTypes.contains(node.type) {
            var range = node.range
            guard range.location >= 0, NSMaxRange(range) <= length else { continue }
            if headingMarkerTypes.contains(node.type) {
                var end = NSMaxRange(range)
                while end < length, text.character(at: end) == 0x20 /* space */ {
                    end += 1
                }
                range = NSRange(location: range.location, length: end - range.location)
            }
            ranges.append(range)
        }
        // Highlight (`==x==`) is an Obsidian extension that the tree-sitter
        // Markdown grammar does NOT recognise, so its delimiters never appear
        // as nodes. Detect balanced spans by scanning the text and fold their
        // `==` delimiter runs into the concealable-marker set, so they obey the
        // same per-logical-line reveal rule as the grammar-driven markers.
        for span in highlightSpans(in: text) {
            ranges.append(span.open)
            ranges.append(span.close)
        }
        return normalize(ranges)
    }

    // MARK: - Highlight (`==x==`) scanning (no grammar support)

    /// A balanced highlight span: its opening/closing `==` delimiter runs and
    /// the styled content between them. All ranges are UTF-16 code units.
    public struct HighlightSpan: Equatable {
        /// The opening `==` delimiter (length 2).
        public let open: NSRange
        /// The closing `==` delimiter (length 2).
        public let close: NSRange
        /// The content between the delimiters (the run to style highlighted).
        public let content: NSRange
    }

    /// Scans `text` for balanced, single-line `==highlight==` spans.
    ///
    /// Honors the spec's gotchas for marker-like inline syntax:
    /// - **Balanced only:** an unmatched opening `==` (e.g. while typing) is
    ///   left raw — only a closing `==` on the same logical line decorates.
    /// - **Escapes:** a `=` preceded by an odd run of backslashes is literal
    ///   and never starts/ends a span.
    /// - **Non-empty / non-blank content:** `====` and `==   ==` are ignored
    ///   (mirrors emphasis flanking — a delimiter must hug real content).
    /// - **Inline scope:** a span never crosses a newline.
    ///
    /// - Parameter text: The document text.
    /// - Returns: Non-overlapping highlight spans in document order.
    public static func highlightSpans(in text: NSString) -> [HighlightSpan] {
        let length = text.length
        guard length >= 4 else { return [] }
        var spans: [HighlightSpan] = []
        var i = 0
        while i < length - 1 {
            guard isDelimiter(at: i, in: text) else {
                i += 1
                continue
            }
            // Found an opening `==` at i; search for a closing `==` on the same
            // line with non-blank content between.
            var j = i + 2
            var found = -1
            while j < length - 1 {
                let unit = text.character(at: j)
                if unit == 0x0A /* newline */ { break }
                if isDelimiter(at: j, in: text) {
                    found = j
                    break
                }
                j += 1
            }
            guard found > i + 2 else {
                i += 1
                continue
            }
            let contentRange = NSRange(location: i + 2, length: found - (i + 2))
            if hasNonBlank(contentRange, in: text) {
                spans.append(
                    HighlightSpan(
                        open: NSRange(location: i, length: 2),
                        close: NSRange(location: found, length: 2),
                        content: contentRange))
                i = found + 2
            } else {
                i += 1
            }
        }
        return spans
    }

    /// The content ranges of every balanced highlight span (the runs to paint
    /// with the highlight background), for the live-preview styling path.
    public static func highlightContentRanges(in text: NSString) -> [NSRange] {
        highlightSpans(in: text).map(\.content)
    }

    /// Whether a `==` delimiter starts at `index` (two `=` with the first not
    /// escaped by an odd run of preceding backslashes).
    private static func isDelimiter(at index: Int, in text: NSString) -> Bool {
        guard index + 1 < text.length else { return false }
        guard text.character(at: index) == 0x3D, text.character(at: index + 1) == 0x3D else {
            return false
        }
        // Count preceding backslashes; an odd count escapes the first `=`.
        var backslashes = 0
        var k = index - 1
        while k >= 0, text.character(at: k) == 0x5C /* backslash */ {
            backslashes += 1
            k -= 1
        }
        return backslashes % 2 == 0
    }

    /// Whether the range contains at least one non-whitespace UTF-16 unit.
    private static func hasNonBlank(_ range: NSRange, in text: NSString) -> Bool {
        for offset in range.location..<NSMaxRange(range) {
            let unit = text.character(at: offset)
            if unit != 0x20 && unit != 0x09 { return true }
        }
        return false
    }

    // MARK: - Active logical lines

    /// Computes the logical-line ranges that the selection (or bare caret)
    /// touches. A zero-length caret counts as touching the line that contains
    /// its location (boundaries inclusive), so the line the caret sits on is
    /// always active. Multi-line selections activate every covered line.
    ///
    /// - Parameters:
    ///   - text: The document text.
    ///   - selections: The current selection ranges (caret = zero length).
    /// - Returns: Merged, sorted active line ranges (each a full `lineRange`).
    public static func activeLineRanges(
        in text: NSString,
        selections: [NSRange]
    ) -> [NSRange] {
        let length = text.length
        var lines: [NSRange] = []
        for selection in selections {
            let clampedLocation = max(0, min(selection.location, length))
            let clampedLength = max(0, min(selection.length, length - clampedLocation))
            let probe = NSRange(location: clampedLocation, length: clampedLength)
            // `lineRange(for:)` on a zero-length range still returns the
            // containing line; for multi-line selections it spans all lines.
            let line = text.lineRange(for: probe)
            lines.append(line)
        }
        return normalize(lines)
    }

    // MARK: - Conceal / reveal decision

    /// Splits marker ranges into those that should be *concealed* (their line
    /// is inactive) and those that should be *revealed* (their line is active).
    ///
    /// A marker belongs to the logical line returned by `lineRange(for:)` at
    /// its start; if that line intersects any active line it is revealed,
    /// otherwise concealed. This implements the spec's per-logical-line rule:
    /// a caret anywhere on a line reveals ALL inline markers on that line.
    ///
    /// - Parameters:
    ///   - text: The document text.
    ///   - selections: Current selection ranges (caret = zero length).
    ///   - nodes: Parse nodes to derive markers from.
    /// - Returns: `concealed` and `revealed` marker-range arrays (sorted).
    public static func resolve(
        in text: NSString,
        selections: [NSRange],
        nodes: [MarkdownSyntaxNode]
    ) -> (concealed: [NSRange], revealed: [NSRange]) {
        let markers = markerRanges(from: nodes, in: text)
        return partition(markers: markers, in: text, selections: selections)
    }

    /// Partitions an ARBITRARY set of marker ranges into concealed vs revealed
    /// using the same per-logical-line reveal rule as `resolve`. Lets
    /// block-level decorations (e.g. blockquote `> ` markers from
    /// `LivePreviewBlockDecorations`) share the inline reveal mechanism: a
    /// caret anywhere on a line reveals every marker on that line.
    public static func partition(
        markers: [NSRange],
        in text: NSString,
        selections: [NSRange]
    ) -> (concealed: [NSRange], revealed: [NSRange]) {
        let activeLines = activeLineRanges(in: text, selections: selections)

        var concealed: [NSRange] = []
        var revealed: [NSRange] = []
        for marker in markers {
            let markerLine = text.lineRange(
                for: NSRange(location: marker.location, length: 0))
            let isActive = activeLines.contains { intersects($0, markerLine) }
            if isActive {
                revealed.append(marker)
            } else {
                concealed.append(marker)
            }
        }
        return (concealed, revealed)
    }

    // MARK: - Helpers

    /// Whether two logical-line ranges overlap. Half-open intervals, so that
    /// adjacent lines (which share an exact boundary at the newline) do NOT
    /// count as overlapping — otherwise a caret on a blank line would bleed a
    /// reveal onto its neighbours. Caret-at-edge cases are already resolved by
    /// mapping the caret to its containing line via `lineRange(for:)`.
    private static func intersects(_ a: NSRange, _ b: NSRange) -> Bool {
        let start = max(a.location, b.location)
        let end = min(NSMaxRange(a), NSMaxRange(b))
        return start < end
    }

    /// Sorts ranges by location and removes exact duplicates.
    private static func normalize(_ ranges: [NSRange]) -> [NSRange] {
        var seen = Set<NSRange>()
        var unique: [NSRange] = []
        for range in ranges where seen.insert(range).inserted {
            unique.append(range)
        }
        return unique.sorted {
            $0.location != $1.location
                ? $0.location < $1.location : $0.length < $1.length
        }
    }
}
