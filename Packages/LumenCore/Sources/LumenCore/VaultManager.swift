//
//  VaultManager.swift
//  LumenCore
//
//  UI-facing vault state: open/close the current vault, persist a recent-vaults
//  list, and reopen the last vault on launch — all via security-scoped
//  bookmarks so access survives across launches under the App Sandbox.
//
//  P1.4 scope: access + persistence only. No file enumeration/IO (P1.5),
//  no file-tree (P1.15), no FSEvents (P1.6).
//

import Foundation
import Observation
import os

/// Errors surfaced while opening or resolving a vault.
public enum VaultError: Error, Sendable, Equatable {
    /// Creating a security-scoped bookmark for the URL failed.
    case bookmarkCreationFailed
    /// `startAccessingSecurityScopedResource()` returned `false`.
    case accessDenied
    /// The bookmarked folder could not be resolved (e.g. moved/deleted).
    case resolutionFailed
}

/// Pure, side-effect-free helpers for the recent-vaults list, kept separate so
/// the add/dedupe/reorder/cap behavior is unit-testable without `UserDefaults`.
public enum RecentVaultsPolicy {
    /// The maximum number of recent vaults to retain.
    public static let cap = 10

    /// Returns a new list with `entry` inserted at the front, any existing
    /// entry for the same path removed (dedupe), and the result capped.
    /// - Parameters:
    ///   - recents: The existing list (front = most recent).
    ///   - entry: The newly opened vault to promote to the front.
    ///   - cap: Maximum entries to keep.
    /// - Returns: The updated, deduped, capped list.
    public static func updating(
        _ recents: [RecentVault],
        adding entry: RecentVault,
        cap: Int = cap
    ) -> [RecentVault] {
        var result = recents.filter { $0.path != entry.path }
        result.insert(entry, at: 0)
        if result.count > cap {
            result.removeLast(result.count - cap)
        }
        return result
    }

    /// Removes any entry matching `path`.
    public static func removing(_ recents: [RecentVault], path: String) -> [RecentVault] {
        recents.filter { $0.path != path }
    }
}

/// Observable manager for the current vault and recent vaults.
@MainActor
@Observable
public final class VaultManager {
    /// The currently open vault, or `nil` when none is open.
    public private(set) var current: Vault?

    /// Recently opened vaults, most-recent first.
    public private(set) var recents: [RecentVault]

    /// Backing store for persistence (injectable for tests).
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let logger = Logger(subsystem: "ai.Lumen", category: "VaultManager")

    /// The URL currently being security-scope accessed (to balance stop calls).
    @ObservationIgnored private var accessedURL: URL?

    private static let recentsKey = "LumenCore.recentVaults"

    /// Creates a manager and (optionally) reopens the most recent vault.
    /// - Parameters:
    ///   - defaults: Persistence store. Defaults to `.standard`.
    ///   - reopenLast: When `true`, attempts to reopen the most-recent vault.
    public init(defaults: UserDefaults = .standard, reopenLast: Bool = true) {
        self.defaults = defaults
        self.recents = Self.loadRecents(from: defaults)
        if reopenLast {
            reopenMostRecent()
        }
    }

    // MARK: - Open / Close

    /// Opens the folder at `url` as the current vault.
    ///
    /// Creates a security-scoped bookmark, persists it to the recents list,
    /// begins security-scoped access, and sets `current`.
    /// - Parameter url: A user-selected folder URL.
    /// - Throws: ``VaultError`` if the bookmark cannot be created or access denied.
    public func openVault(at url: URL) throws {
        let bookmark: Data
        do {
            bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            logger.error(
                "Bookmark creation failed: \(error.localizedDescription, privacy: .public)")
            throw VaultError.bookmarkCreationFailed
        }
        try activate(url: url, bookmark: bookmark)
    }

    /// Closes the current vault and stops security-scoped access.
    public func closeVault() {
        stopAccessing()
        current = nil
    }

    // MARK: - Recents

    /// Reopens a recent vault by resolving its stored bookmark.
    /// - Parameter recent: The recent entry to reopen.
    /// - Throws: ``VaultError/resolutionFailed`` if it can no longer be resolved.
    public func openRecent(_ recent: RecentVault) throws {
        guard let url = resolve(recent) else {
            recents = RecentVaultsPolicy.removing(recents, path: recent.path)
            persistRecents()
            throw VaultError.resolutionFailed
        }
        try activate(url: url, bookmark: recent.bookmark)
    }

    // MARK: - Private

    /// Begins access, updates `current`, and records the vault in recents.
    private func activate(url: URL, bookmark: Data) throws {
        stopAccessing()
        guard url.startAccessingSecurityScopedResource() else {
            throw VaultError.accessDenied
        }
        accessedURL = url

        let vault = Vault(root: url)
        current = vault

        let entry = RecentVault(name: vault.name, path: url.path, bookmark: bookmark)
        recents = RecentVaultsPolicy.updating(recents, adding: entry)
        persistRecents()
    }

    /// Resolves a recent's bookmark to a URL, recreating it if stale.
    /// - Returns: The resolved URL, or `nil` if it can't be resolved.
    private func resolve(_ recent: RecentVault) -> URL? {
        var isStale = false
        guard
            let url = try? URL(
                resolvingBookmarkData: recent.bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        else {
            return nil
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        if isStale {
            // Recreate the bookmark while we (briefly) have access to the URL.
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            if let fresh = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                let refreshed = RecentVault(
                    name: recent.name, path: recent.path,
                    bookmark: fresh, lastOpened: recent.lastOpened)
                recents = RecentVaultsPolicy.updating(
                    RecentVaultsPolicy.removing(recents, path: recent.path),
                    adding: refreshed
                )
                persistRecents()
            }
        }
        return url
    }

    /// Attempts to reopen the most-recent vault at launch, failing gracefully.
    private func reopenMostRecent() {
        guard let mostRecent = recents.first else { return }
        do {
            try openRecent(mostRecent)
        } catch {
            logger.notice(
                "Could not reopen last vault: \(String(describing: error), privacy: .public)")
        }
    }

    /// Stops any in-progress security-scoped access.
    private func stopAccessing() {
        if let accessedURL {
            accessedURL.stopAccessingSecurityScopedResource()
            self.accessedURL = nil
        }
    }

    // MARK: - Persistence

    private func persistRecents() {
        guard let data = try? JSONEncoder().encode(recents) else { return }
        defaults.set(data, forKey: Self.recentsKey)
    }

    private static func loadRecents(from defaults: UserDefaults) -> [RecentVault] {
        guard let data = defaults.data(forKey: recentsKey),
            let decoded = try? JSONDecoder().decode([RecentVault].self, from: data)
        else {
            return []
        }
        return decoded
    }
}
