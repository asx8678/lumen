//
//  DocumentSession.swift
//  LumenCore
//
//  The open-document model for the editor: tracks the currently open file, its
//  in-memory text, and a dirty/saved flag, backed by `FileService` (P1.5).
//
//  P1.15 scope: a SINGLE open document. It is deliberately shaped so P1.16 can
//  wrap a collection of these (one per tab) with an active selection, without
//  rewriting the load/save/dirty logic — see `open`/`save`/`close`.
//

import Foundation
import Observation

/// Observable state for the single open document.
///
/// Tab-readiness: P1.16 can introduce a `documents: [DocumentSession]` (or a
/// store keyed by URL) and switch the active one; each tab owns one of these.
@MainActor
@Observable
public final class DocumentSession: Identifiable {
    /// Stable identity for tab tracking (P1.16).
    public nonisolated let id = UUID()

    /// The URL of the open file, or `nil` when nothing is open.
    public private(set) var url: URL?

    /// The editor's working text. Mutating it updates ``isDirty``.
    public var text: String {
        didSet {
            guard !isApplyingLoad else { return }
            isDirty = (text != savedText)
        }
    }

    /// Whether `text` differs from what's on disk.
    public private(set) var isDirty: Bool

    /// Set when the file changed externally while we hold unsaved edits (P1.6).
    /// The UI surfaces a warning; full conflict resolution is Phase 3.
    public internal(set) var hasExternalConflict: Bool = false

    /// The last-known on-disk contents (the baseline for dirtiness).
    @ObservationIgnored private var savedText: String
    /// Guards `text.didSet` while we apply a load programmatically.
    @ObservationIgnored private var isApplyingLoad = false
    @ObservationIgnored private let files: FileService

    /// Creates an empty session.
    public init(files: FileService) {
        self.files = files
        self.url = nil
        self.text = ""
        self.savedText = ""
        self.isDirty = false
    }

    /// Loads `url`'s contents into the session, replacing the current document.
    /// - Parameter url: The Markdown file to open.
    public func open(_ url: URL) async throws {
        let contents = try await files.read(url)
        isApplyingLoad = true
        text = contents
        isApplyingLoad = false
        savedText = contents
        self.url = url
        isDirty = false
        hasExternalConflict = false
    }

    /// Saves the current text back to disk (atomic via `FileService`).
    /// No-op when nothing is open.
    public func save() async throws {
        guard let url else { return }
        let toWrite = text
        try await files.write(toWrite, to: url)
        savedText = toWrite
        isDirty = (text != savedText)
        // Saving establishes a new baseline and resolves any conflict in our
        // favor (the on-disk file now matches our text).
        hasExternalConflict = false
    }

    /// Saves only if there are unsaved changes (used by autosave so clean
    /// documents never write).
    /// - Returns: `true` if a write happened.
    @discardableResult
    public func autosaveIfNeeded() async throws -> Bool {
        guard url != nil, isDirty else { return false }
        try await save()
        return true
    }

    /// The hash of the saved baseline — what we believe is on disk. Used by
    /// reconciliation to detect (and ignore) our own writes (P1.6).
    public var baselineHash: String { NoteIndexing.contentHash(of: savedText) }

    /// Reconciles an external on-disk change with this document (P1.6).
    ///
    /// Reads the file, compares its hash to our saved baseline, and either
    /// ignores (our own write / no real change), reloads (disk changed, no
    /// unsaved edits), or flags a conflict (disk changed under unsaved edits).
    public func reconcileExternalChange() async {
        guard let url else { return }
        // A read failure (e.g. the file was deleted/moved) is left to Phase 3.
        guard let onDisk = try? await files.read(url) else { return }
        let decision = FileReconciliation.decide(
            onDiskHash: NoteIndexing.contentHash(of: onDisk),
            baselineHash: baselineHash,
            isDirty: isDirty)
        switch decision {
        case .ignore:
            break
        case .reload:
            applyLoadedText(onDisk)
        case .warnConflict:
            hasExternalConflict = true
        }
    }

    /// Dismisses the external-conflict warning, keeping the in-memory edits
    /// (the user can then ⌘S to overwrite the on-disk version).
    public func dismissConflict() {
        hasExternalConflict = false
    }

    /// Force-reloads the document from disk, discarding any unsaved edits
    /// (used to resolve a conflict in favor of the on-disk version).
    public func reloadFromDisk() async {
        guard let url, let onDisk = try? await files.read(url) else { return }
        applyLoadedText(onDisk)
    }

    /// Replaces the working text with loaded content and resets dirty/conflict.
    private func applyLoadedText(_ contents: String) {
        isApplyingLoad = true
        text = contents
        isApplyingLoad = false
        savedText = contents
        isDirty = false
        hasExternalConflict = false
    }

    /// Clears the session (no file open).
    public func close() {
        isApplyingLoad = true
        text = ""
        isApplyingLoad = false
        savedText = ""
        url = nil
        isDirty = false
    }
}
