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
        return normalize(ranges)
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
