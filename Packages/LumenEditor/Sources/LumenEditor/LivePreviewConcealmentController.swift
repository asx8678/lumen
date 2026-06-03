//
//  LivePreviewConcealmentController.swift
//  LumenEditor
//
//  P2.2.1 (lumen-nmm.5) — SPIKE: the TextKit 2 *mechanism* that consumes the
//  conceal/reveal decision from `LivePreviewDecorations` and hides Markdown
//  markers WITHOUT mutating the backing text store.
//
//  Mechanism: `NSTextContentStorageDelegate.textContentStorage(_:textParagraph
//  With:)`. TextKit 2 asks the delegate for the *display* paragraph for each
//  backing paragraph range. We return an `NSTextParagraph` whose attributed
//  string has the concealed marker code units removed — the backing
//  `NSTextStorage` is never touched, so the document text, undo/redo, and copy
//  all still operate on raw Markdown. Concealing fewer characters than the
//  backing paragraph is the documented TextKit 2 way to hide syntax (the same
//  shape Apple's TextKit 2 markdown sample uses).
//
//  Geometry is correct *by construction*: the layout fragment is built from the
//  shortened display string, so glyph advances/line breaks reflect only the
//  visible characters — no zero-width-font hacks (which the spec flags as
//  unreliable). The known caveat — backing⇄display index mapping for caret
//  navigation across concealed runs — is documented in the GO/NO-GO writeup.
//
//  This controller is INERT unless `isEnabled` is set (the feature flag), so
//  the default shipping editor path is byte-for-byte unchanged.
//

import AppKit

/// Bridges the pure conceal/reveal decision onto a TextKit 2 content storage.
///
/// The controller is the `NSTextContentStorageDelegate`. When enabled it
/// rewrites each paragraph's *display* string to drop the marker ranges that
/// `LivePreviewDecorations` resolved as concealed for the current selection.
@MainActor
public final class LivePreviewConcealmentController: NSObject,
    @preconcurrency NSTextContentStorageDelegate
{
    /// Feature flag. While `false`, the delegate returns `nil` for every
    /// paragraph, so TextKit 2 uses the verbatim backing string (default path).
    public var isEnabled: Bool = false

    /// Document-coordinate marker ranges currently concealed (UTF-16). Set via
    /// `update(concealed:)`, which also reports which paragraphs changed so the
    /// caller can invalidate only those (viewport-only + active-line diff).
    private(set) var concealedRanges: [NSRange] = []

    /// A display-string substitution: replace a backing range with a string
    /// without mutating the store. Used for persistent list bullets (`- ` →
    /// `• `), which — unlike concealed markers — stay substituted even on the
    /// active line (per the spec).
    struct Substitution: Equatable {
        let range: NSRange
        let replacement: String
    }

    /// Current bullet substitutions (document coordinates).
    private(set) var substitutions: [Substitution] = []

    /// Per-paragraph indentation to apply to the display string for list items
    /// and blockquotes (head indent + hang indent). Keyed by a backing range
    /// that falls inside the target paragraph; the whole display paragraph
    /// receives the style. Stored as raw values so the controller stays
    /// font-agnostic — the coordinator builds the `NSParagraphStyle`.
    private(set) var paragraphIndents: [ParagraphIndent] = []

    /// An indentation directive for one paragraph.
    struct ParagraphIndent: Equatable {
        /// A backing offset inside the target paragraph.
        let anchor: Int
        /// Indent of the first display line (points).
        let firstLineHeadIndent: CGFloat
        /// Indent of wrapped continuation lines (points) — the hang indent.
        let headIndent: CGFloat
    }

    /// Replaces the concealed-range set and returns `true` if it changed.
    ///
    /// - Parameter ranges: The new concealed marker ranges (already restricted
    ///   to the viewport by the caller).
    /// - Returns: `true` when the set differs from the previous one.
    @discardableResult
    public func update(concealed ranges: [NSRange]) -> Bool {
        let next = ranges.sorted {
            $0.location != $1.location
                ? $0.location < $1.location : $0.length < $1.length
        }
        guard next != concealedRanges else { return false }
        concealedRanges = next
        return true
    }

    /// Replaces the bullet-substitution set and returns `true` if it changed.
    @discardableResult
    func update(substitutions next: [Substitution]) -> Bool {
        let sorted = next.sorted { $0.range.location < $1.range.location }
        guard sorted != substitutions else { return false }
        substitutions = sorted
        return true
    }

    /// Replaces the paragraph-indent set and returns `true` if it changed.
    @discardableResult
    func update(paragraphIndents next: [ParagraphIndent]) -> Bool {
        let sorted = next.sorted { $0.anchor < $1.anchor }
        guard sorted != paragraphIndents else { return false }
        paragraphIndents = sorted
        return true
    }

    /// Whether the delegate currently has anything to substitute on display.
    var hasDisplaySubstitutions: Bool {
        !concealedRanges.isEmpty || !substitutions.isEmpty || !paragraphIndents.isEmpty
    }

    /// Clears all concealment (used when the feature flag is turned off).
    public func reset() {
        concealedRanges = []
        substitutions = []
        paragraphIndents = []
    }

    // MARK: - NSTextContentStorageDelegate

    public func textContentStorage(
        _ textContentStorage: NSTextContentStorage,
        textParagraphWith range: NSRange
    ) -> NSTextParagraph? {
        guard isEnabled, hasDisplaySubstitutions,
            let backing = textContentStorage.textStorage
        else { return nil }

        // Build a single ordered edit list (deletions for concealed markers,
        // string replacements for bullets), mapped to paragraph-local
        // coordinates and sorted high→low so earlier edits don't shift the
        // offsets of not-yet-applied ones.
        struct Edit {
            let range: NSRange
            let replacement: String?  // nil = delete
        }
        var edits: [Edit] = []
        for concealed in concealedRanges {
            let hit = NSIntersectionRange(concealed, range)
            guard hit.length > 0 else { continue }
            edits.append(
                Edit(
                    range: NSRange(
                        location: hit.location - range.location, length: hit.length),
                    replacement: nil))
        }
        for substitution in substitutions {
            let hit = NSIntersectionRange(substitution.range, range)
            guard hit.length > 0 else { continue }
            edits.append(
                Edit(
                    range: NSRange(
                        location: hit.location - range.location, length: hit.length),
                    replacement: substitution.replacement))
        }

        // Indentation that targets this paragraph (anchor inside the range).
        let indent = paragraphIndents.first { range.contains($0.anchor) }

        guard !edits.isEmpty || indent != nil else { return nil }
        edits.sort { $0.range.location > $1.range.location }

        let display = NSMutableAttributedString(
            attributedString: backing.attributedSubstring(from: range))
        for edit in edits where NSMaxRange(edit.range) <= display.length {
            if let replacement = edit.replacement {
                let attrs = display.attributes(
                    at: edit.range.location, effectiveRange: nil)
                display.replaceCharacters(
                    in: edit.range,
                    with: NSAttributedString(string: replacement, attributes: attrs))
            } else {
                display.deleteCharacters(in: edit.range)
            }
        }

        if let indent, display.length > 0 {
            let whole = NSRange(location: 0, length: display.length)
            let base =
                (display.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
                    as? NSParagraphStyle ?? .default)
            // swiftlint:disable:next force_cast
            let style = base.mutableCopy() as! NSMutableParagraphStyle
            style.firstLineHeadIndent = indent.firstLineHeadIndent
            style.headIndent = indent.headIndent
            display.addAttribute(.paragraphStyle, value: style, range: whole)
        }
        return NSTextParagraph(attributedString: display)
    }
}
