//
//  TabPersistence.swift
//  LumenCore
//
//  Persists the set of open editor tabs (P1.16) so they can be restored after
//  relaunch. Open files are stored as paths RELATIVE to the vault root, keyed by
//  vault, plus the active index. Restore is resilient: files that no longer
//  exist are silently skipped.
//

import Foundation

/// A serializable snapshot of the open tabs for one vault.
public struct TabsSnapshot: Codable, Equatable, Sendable {
    /// Open files as vault-root-relative paths, in tab order.
    public var relativePaths: [String]
    /// The active tab's index into `relativePaths`.
    public var activeIndex: Int
    /// Per-tab presentation modes (P2.1.1), parallel to `relativePaths`. May be
    /// shorter (or empty) than `relativePaths` — missing entries default to
    /// `.edit`, so legacy snapshots decode cleanly.
    public var viewModes: [EditorViewMode]

    public init(
        relativePaths: [String],
        activeIndex: Int,
        viewModes: [EditorViewMode] = []
    ) {
        self.relativePaths = relativePaths
        self.activeIndex = activeIndex
        self.viewModes = viewModes
    }

    /// Decodes, defaulting `viewModes` to empty for legacy snapshots.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.relativePaths = try c.decode([String].self, forKey: .relativePaths)
        self.activeIndex = try c.decode(Int.self, forKey: .activeIndex)
        self.viewModes =
            try c.decodeIfPresent([EditorViewMode].self, forKey: .viewModes) ?? []
    }

    /// The persisted mode for `index`, defaulting to `.edit`.
    public func viewMode(at index: Int) -> EditorViewMode {
        viewModes.indices.contains(index) ? viewModes[index] : .edit
    }

    /// An empty snapshot (no open tabs).
    public static let empty = TabsSnapshot(relativePaths: [], activeIndex: 0)
}

/// Reads/writes ``TabsSnapshot`` to `UserDefaults`, keyed by vault root path.
public struct TabStore {
    private let defaults: UserDefaults
    private static let prefix = "LumenTabs."

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(for vaultRoot: URL) -> String {
        Self.prefix + vaultRoot.standardizedFileURL.path
    }

    /// Persists `snapshot` for the given vault.
    public func save(_ snapshot: TabsSnapshot, vaultRoot: URL) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key(for: vaultRoot))
    }

    /// Loads the snapshot for the given vault (empty if none/corrupt).
    public func load(vaultRoot: URL) -> TabsSnapshot {
        guard let data = defaults.data(forKey: key(for: vaultRoot)),
            let snapshot = try? JSONDecoder().decode(TabsSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }

    /// Resolves a snapshot into existing absolute URLs + a clamped active index.
    ///
    /// Missing files are skipped; the active index is remapped to the surviving
    /// tabs (clamped into range).
    /// - Parameters:
    ///   - snapshot: The persisted snapshot.
    ///   - vaultRoot: The vault root the relative paths are based on.
    ///   - exists: Predicate testing whether a URL still exists (injectable).
    /// - Returns: Surviving URLs in order, their per-tab modes (parallel to
    ///   `urls`), and the active index (or `nil`).
    public static func resolve(
        _ snapshot: TabsSnapshot,
        vaultRoot: URL,
        exists: (URL) -> Bool
    ) -> (urls: [URL], modes: [EditorViewMode], activeIndex: Int?) {
        var urls: [URL] = []
        var modes: [EditorViewMode] = []
        var newActive: Int?
        for (offset, path) in snapshot.relativePaths.enumerated() {
            let url = TabSupport.resolve(relativePath: path, root: vaultRoot)
            guard exists(url) else { continue }
            if offset <= snapshot.activeIndex { newActive = urls.count }
            urls.append(url)
            modes.append(snapshot.viewMode(at: offset))
        }
        guard !urls.isEmpty else { return ([], [], nil) }
        let clamped = min(max(newActive ?? 0, 0), urls.count - 1)
        return (urls, modes, clamped)
    }
}
