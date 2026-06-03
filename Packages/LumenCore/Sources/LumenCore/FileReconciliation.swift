//
//  FileReconciliation.swift
//  LumenCore
//
//  Pure decision logic for reconciling an external filesystem change against an
//  open document (P1.6). Kept separate from FSEvents so it is unit-testable.
//
//  Self-write suppression is intrinsic: a document's baseline hash is the hash
//  of what we last read/wrote (`savedText`). After our own autosave/⌘S the
//  baseline already equals the on-disk contents, so the resulting FSEvent
//  resolves to `.ignore` — no reload loop, no fighting the editor.
//

import Foundation

/// Decides what to do when a watched file changes on disk.
public enum FileReconciliation {
    /// The action to take for an external change.
    public enum Decision: Equatable, Sendable {
        /// On-disk content matches our baseline (our own write, or a no-op
        /// event) — do nothing.
        case ignore
        /// Disk changed and we have no unsaved edits — safe to reload.
        case reload
        /// Disk changed but we have unsaved edits — warn before overwriting
        /// (full conflict resolution is Phase 3).
        case warnConflict
    }

    /// - Parameters:
    ///   - onDiskHash: Hash of the file's current on-disk contents.
    ///   - baselineHash: Hash of the document's saved baseline (`savedText`).
    ///   - isDirty: Whether the document has unsaved edits.
    public static func decide(
        onDiskHash: String,
        baselineHash: String,
        isDirty: Bool
    ) -> Decision {
        // Disk equals what we believe is saved -> nothing external happened
        // (covers our own writes and duplicate/echo events).
        if onDiskHash == baselineHash { return .ignore }
        return isDirty ? .warnConflict : .reload
    }
}
