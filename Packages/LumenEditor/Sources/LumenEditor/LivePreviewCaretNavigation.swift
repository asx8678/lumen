//
//  LivePreviewCaretNavigation.swift
//  LumenEditor
//
//  P2.2.1a (lumen-nmm.17) — caret atomicity over concealed marker runs.
//
//  When Live Preview hides a marker run (e.g. `**`, `# `, a `==` delimiter) the
//  display string is SHORTER than the backing store, but selection lives in
//  *backing* coordinates. AppKit can therefore propose a caret/selection that
//  lands *inside* a concealed run — which would let the caret sit between two
//  invisible characters, or let an arrow key appear to "stick". The spec's
//  caret-atomicity rule (gotcha #10) says navigation must treat each concealed
//  run as ATOMIC: the caret steps over the whole run, and a selection that
//  partially covers a run expands to include it (so boundaries land on real,
//  visible characters and copied text is well-formed Markdown).
//
//  This type is the PURE, headlessly-testable adjustment applied from the text
//  view's `willChangeSelection` delegate hook (feature-flagged). It never
//  touches AppKit; it maps a proposed selection + the previous selection + the
//  currently concealed runs onto a corrected selection.
//
//  Note on "flip-to-source on entry": the per-logical-line reveal rule
//  (`LivePreviewDecorations`) already removes a line's markers from the
//  concealed set the moment the caret's line becomes active. So concealed runs
//  only ever exist on lines OTHER than the caret's current line; the timing gap
//  this adjustment closes is the instant of *crossing into* a line whose
//  markers are still concealed (vertical motion, click, selection extension).
//

import Foundation

/// Pure caret/selection adjustment that makes concealed marker runs atomic.
///
/// All offsets/ranges are UTF-16 code units (backing-store coordinates).
public enum LivePreviewCaretNavigation {
    /// Direction a bare caret is moving, inferred from the previous location.
    private enum Direction {
        case forward
        case backward
        case none
    }

    /// Adjusts a proposed selection so it never splits a concealed marker run.
    ///
    /// - For a **bare caret** that lands strictly inside a concealed run, the
    ///   caret snaps over the whole run — to its trailing edge when moving
    ///   forward (Right/Down/End), to its leading edge when moving backward
    ///   (Left/Up/Home), or to the nearer edge when there is no clear
    ///   direction (e.g. a mouse click).
    /// - For a **ranged selection**, each endpoint that falls inside a run is
    ///   pushed outward (lower bound → run start, upper bound → run end) so the
    ///   selection covers entire runs and copies as well-formed Markdown.
    ///
    /// - Parameters:
    ///   - proposed: The selection AppKit wants to set (caret = zero length).
    ///   - previous: The selection before this change (used for direction).
    ///   - concealed: The currently concealed marker runs (any order).
    ///   - length: The backing document length, for clamping.
    /// - Returns: The corrected selection (equal to `proposed` when already
    ///   atomic).
    public static func adjustedSelection(
        proposed: NSRange,
        previous: NSRange,
        concealed: [NSRange],
        length: Int
    ) -> NSRange {
        guard !concealed.isEmpty else { return proposed }
        let runs = concealed.sorted { $0.location < $1.location }

        if proposed.length == 0 {
            let direction = direction(from: previous, to: proposed)
            let snapped = snap(caret: proposed.location, direction: direction, runs: runs)
            return NSRange(location: clamp(snapped, length), length: 0)
        }

        // Ranged selection: expand endpoints outward off any run interior.
        var lower = proposed.location
        var upper = NSMaxRange(proposed)
        if let run = runContaining(lower, in: runs) {
            lower = run.location
        }
        if let run = runContaining(upper, in: runs) {
            upper = NSMaxRange(run)
        }
        lower = clamp(lower, length)
        upper = clamp(upper, length)
        return NSRange(location: lower, length: max(0, upper - lower))
    }

    // MARK: - Helpers

    /// Snaps a caret out of any run it sits *strictly inside* (an edge position
    /// is already valid). Picks the edge per the movement direction.
    private static func snap(caret: Int, direction: Direction, runs: [NSRange]) -> Int {
        guard let run = runStrictlyContaining(caret, in: runs) else { return caret }
        switch direction {
        case .forward:
            return NSMaxRange(run)
        case .backward:
            return run.location
        case .none:
            let toStart = caret - run.location
            let toEnd = NSMaxRange(run) - caret
            return toEnd <= toStart ? NSMaxRange(run) : run.location
        }
    }

    private static func direction(from previous: NSRange, to proposed: NSRange) -> Direction {
        // Compare against whichever previous endpoint the caret left from.
        let anchors = [previous.location, NSMaxRange(previous)]
        if proposed.location > anchors.max() ?? previous.location { return .forward }
        if proposed.location < anchors.min() ?? previous.location { return .backward }
        return .none
    }

    /// The run that strictly contains `offset` (offset is between, not on,
    /// the run's edges), or `nil`.
    private static func runStrictlyContaining(_ offset: Int, in runs: [NSRange]) -> NSRange? {
        for run in runs where offset > run.location && offset < NSMaxRange(run) {
            return run
        }
        return nil
    }

    /// The run that contains `offset` inclusive of edges, or `nil`.
    private static func runContaining(_ offset: Int, in runs: [NSRange]) -> NSRange? {
        for run in runs where offset > run.location && offset < NSMaxRange(run) {
            return run
        }
        return nil
    }

    private static func clamp(_ value: Int, _ length: Int) -> Int {
        min(max(0, value), length)
    }
}
