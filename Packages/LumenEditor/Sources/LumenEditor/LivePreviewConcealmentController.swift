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

    /// Clears all concealment (used when the feature flag is turned off).
    public func reset() {
        concealedRanges = []
    }

    // MARK: - NSTextContentStorageDelegate

    public func textContentStorage(
        _ textContentStorage: NSTextContentStorage,
        textParagraphWith range: NSRange
    ) -> NSTextParagraph? {
        guard isEnabled, !concealedRanges.isEmpty,
            let backing = textContentStorage.textStorage
        else { return nil }

        // Collect concealed ranges that fall in this paragraph, mapped to
        // paragraph-local coordinates, sorted high→low so deletions don't
        // shift not-yet-processed offsets.
        var local: [NSRange] = []
        for concealed in concealedRanges {
            let hit = NSIntersectionRange(concealed, range)
            guard hit.length > 0 else { continue }
            local.append(
                NSRange(location: hit.location - range.location, length: hit.length))
        }
        guard !local.isEmpty else { return nil }
        local.sort { $0.location > $1.location }

        let display = NSMutableAttributedString(
            attributedString: backing.attributedSubstring(from: range))
        for marker in local where NSMaxRange(marker) <= display.length {
            display.deleteCharacters(in: marker)
        }
        return NSTextParagraph(attributedString: display)
    }
}
