//
//  Vault.swift
//  LumenCore
//
//  Value types describing an opened vault and a persisted recent entry.
//
//  P1.4 scope: identity + access only. File enumeration/IO is P1.5; this type
//  never reads directory contents.
//

import Foundation

/// An opened vault: a folder on disk that Lumen treats as a workspace root.
public struct Vault: Sendable, Identifiable, Hashable {
    /// Stable identity derived from the resolved file URL.
    public var id: URL { root }

    /// The root directory of the vault.
    public let root: URL

    /// Human-readable display name (defaults to the folder's last path component).
    public let name: String

    /// When the vault was last opened.
    public let lastOpened: Date

    /// Creates a vault.
    /// - Parameters:
    ///   - root: The vault's root directory URL.
    ///   - name: Optional display name; defaults to the folder name.
    ///   - lastOpened: Timestamp; defaults to now.
    public init(root: URL, name: String? = nil, lastOpened: Date = .now) {
        self.root = root
        self.name = name ?? root.lastPathComponent
        self.lastOpened = lastOpened
    }
}

/// A persisted entry in the "recent vaults" list.
///
/// Stores the security-scoped bookmark `Data` so the folder can be reopened
/// across launches, plus a cached display name and path for UI without needing
/// to resolve the bookmark first.
public struct RecentVault: Sendable, Identifiable, Hashable, Codable {
    /// Stable identity (the cached path string).
    public var id: String { path }

    /// Cached display name (folder name at the time it was opened).
    public let name: String

    /// Cached filesystem path (for display + dedupe).
    public let path: String

    /// The security-scoped bookmark used to resolve the folder later.
    public let bookmark: Data

    /// When this vault was last opened.
    public let lastOpened: Date

    public init(name: String, path: String, bookmark: Data, lastOpened: Date = .now) {
        self.name = name
        self.path = path
        self.bookmark = bookmark
        self.lastOpened = lastOpened
    }
}
