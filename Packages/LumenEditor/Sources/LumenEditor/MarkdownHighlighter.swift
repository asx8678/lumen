//
//  MarkdownHighlighter.swift
//  LumenEditor
//
//  Lightweight, regex / line-based Markdown syntax HIGHLIGHTER (P1.12).
//
//  This colorizes markers — it does NOT render/hide them (no WYSIWYG; that is
//  Phase 2). It is intentionally not an AST/tree-sitter parser. Highlighting is
//  computed for an arbitrary character range so the editor can re-style only a
//  changed paragraph or the visible viewport, never the whole document.
//

import AppKit

/// Computes Markdown highlighting attributes for a range of text.
///
/// The highlighter is stateless and `Sendable`; callers pass the full text plus
/// the sub-range they want styled. Block tokens are detected per line; inline
/// tokens (code, bold, italic, links) are matched within each line.
public struct MarkdownHighlighter: Sendable {
    public init() {}

    // MARK: - Precompiled patterns

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are compile-time constants; a failure is a programmer error.
        guard let re = try? NSRegularExpression(pattern: pattern) else {
            assertionFailure("Invalid highlighter regex: \(pattern)")
            return NSRegularExpression()
        }
        return re
    }

    private static let headingRE = regex(#"^(#{1,6})\s+\S.*$"#)
    private static let fenceRE = regex(#"^\s*```.*$"#)
    private static let blockquoteRE = regex(#"^\s*(>+)"#)
    private static let listRE = regex(#"^(\s*)([-*+]|\d+\.)\s+"#)
    private static let inlineCodeRE = regex(#"`[^`\n]+`"#)
    private static let boldRE = regex(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private static let italicRE = regex(#"(?<![\*_])([\*_])(?=\S)([^\*_\n]+)(?<=\S)\1(?![\*_])"#)
    private static let linkRE = regex(#"\[([^\]\n]+)\]\(([^)\n]+)\)"#)

    /// A styled span: a character range plus the attributes to apply.
    public struct StyledRange {
        public let range: NSRange
        public let attributes: [NSAttributedString.Key: Any]
    }

    // MARK: - Public API

    /// Computes highlighting spans for `range` within `text`.
    ///
    /// - Parameters:
    ///   - text: The full document text.
    ///   - range: The character sub-range to style (typically a paragraph or the
    ///     visible viewport). It is clamped to the text bounds.
    ///   - theme: The colors/fonts to apply.
    /// - Returns: Styled spans whose ranges lie within `range`.
    ///
    /// - Note: Fenced-code detection is performed within the scanned range only;
    ///   a code block that straddles the top of the viewport may briefly style
    ///   incorrectly until scrolled into full view. This keeps the scan
    ///   viewport-scoped (no full-document pass).
    public func styledRanges(
        in text: String,
        range: NSRange,
        theme: MarkdownHighlightTheme
    ) -> [StyledRange] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        let scan = NSIntersectionRange(range, full)
        guard scan.length > 0 else { return [] }

        var spans: [StyledRange] = []
        var insideFence = false

        ns.enumerateSubstrings(in: scan, options: [.byLines, .substringNotRequired]) {
            _, lineRange, _, _ in
            let line = ns.substring(with: lineRange)

            // Fenced code blocks (the ``` lines + everything between).
            if Self.fenceRE.firstMatch(
                in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
            {
                spans.append(
                    StyledRange(
                        range: lineRange,
                        attributes: [
                            .foregroundColor: theme.fenceColor,
                            .font: theme.baseFont,
                        ]))
                insideFence.toggle()
                return
            }
            if insideFence {
                spans.append(
                    StyledRange(
                        range: lineRange,
                        attributes: [
                            .foregroundColor: theme.codeColor,
                            .font: theme.baseFont,
                        ]))
                return
            }

            self.styleLine(line, lineRange: lineRange, theme: theme, into: &spans)
        }

        return spans
    }

    // MARK: - Per-line styling

    private func styleLine(
        _ line: String,
        lineRange: NSRange,
        theme: MarkdownHighlightTheme,
        into spans: inout [StyledRange]
    ) {
        let lineNS = line as NSString
        let local = NSRange(location: 0, length: lineNS.length)

        // Headings color the whole line.
        if Self.headingRE.firstMatch(in: line, range: local) != nil {
            spans.append(
                StyledRange(
                    range: lineRange,
                    attributes: [
                        .foregroundColor: theme.headingColor,
                        .font: theme.boldFont,
                    ]))
            return
        }

        // Blockquote markers.
        if let m = Self.blockquoteRE.firstMatch(in: line, range: local) {
            spans.append(
                StyledRange(
                    range: offset(m.range(at: 1), by: lineRange.location),
                    attributes: [
                        .foregroundColor: theme.quoteColor,
                        .font: theme.boldFont,
                    ]))
        }

        // List markers.
        if let m = Self.listRE.firstMatch(in: line, range: local) {
            spans.append(
                StyledRange(
                    range: offset(m.range(at: 2), by: lineRange.location),
                    attributes: [
                        .foregroundColor: theme.listMarkerColor,
                        .font: theme.boldFont,
                    ]))
        }

        // Inline tokens.
        spans.append(
            contentsOf: matches(Self.linkRE, in: line, lineRange: lineRange) { match in
                var out: [StyledRange] = []
                if match.numberOfRanges >= 3 {
                    out.append(
                        StyledRange(
                            range: offset(match.range(at: 1), by: lineRange.location),
                            attributes: [
                                .foregroundColor: theme.linkTextColor,
                                .underlineStyle: NSUnderlineStyle.single.rawValue,
                            ]))
                    out.append(
                        StyledRange(
                            range: offset(match.range(at: 2), by: lineRange.location),
                            attributes: [.foregroundColor: theme.linkURLColor]))
                }
                return out
            })

        spans.append(
            contentsOf: matches(Self.boldRE, in: line, lineRange: lineRange) { match in
                [
                    StyledRange(
                        range: offset(match.range, by: lineRange.location),
                        attributes: [
                            .foregroundColor: theme.emphasisColor,
                            .font: theme.boldFont,
                        ])
                ]
            })

        spans.append(
            contentsOf: matches(Self.italicRE, in: line, lineRange: lineRange) { match in
                [
                    StyledRange(
                        range: offset(match.range, by: lineRange.location),
                        attributes: [
                            .foregroundColor: theme.emphasisColor,
                            .font: theme.italicFont,
                        ])
                ]
            })

        spans.append(
            contentsOf: matches(Self.inlineCodeRE, in: line, lineRange: lineRange) { match in
                [
                    StyledRange(
                        range: offset(match.range, by: lineRange.location),
                        attributes: [
                            .foregroundColor: theme.codeColor,
                            .font: theme.baseFont,
                        ])
                ]
            })
    }

    // MARK: - Helpers

    private func matches(
        _ re: NSRegularExpression,
        in line: String,
        lineRange: NSRange,
        _ transform: (NSTextCheckingResult) -> [StyledRange]
    ) -> [StyledRange] {
        let lineNS = line as NSString
        let local = NSRange(location: 0, length: lineNS.length)
        var out: [StyledRange] = []
        re.enumerateMatches(in: line, range: local) { match, _, _ in
            guard let match else { return }
            out.append(contentsOf: transform(match))
        }
        return out
    }

    private func offset(_ range: NSRange, by delta: Int) -> NSRange {
        guard range.location != NSNotFound else { return range }
        return NSRange(location: range.location + delta, length: range.length)
    }
}
