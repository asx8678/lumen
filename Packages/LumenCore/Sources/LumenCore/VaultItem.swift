//
//  VaultItem.swift
//  LumenCore
//
//  Value types describing the contents of a vault as produced by `FileService`.
//
//  P1.5 scope: a Sendable snapshot of the filesystem tree. No UI, no live
//  watching (FSEvents is P1.6), no metadata parsing (frontmatter is P1.7).
//

import Foundation

/// The kind of a vault item, used to drive display and filtering.
public enum VaultItemKind: Sendable, Hashable {
    /// A directory.
    case folder
    /// A Markdown document (`.md` / `.markdown`).
    case markdown
    /// Any other file (an "attachment" — images, PDFs, etc.).
    case other
}

/// An immutable snapshot of a single item in a vault.
///
/// Folders carry their `children`; files have an empty `children` array. The
/// tree is produced by ``FileService/enumerate(_:)`` and is safe to pass across
/// concurrency domains.
public struct VaultItem: Sendable, Identifiable, Hashable {
    /// Stable identity (the file URL).
    public var id: URL { url }

    /// The item's file URL.
    public let url: URL
    /// Display name (last path component).
    public let name: String
    /// The item's kind.
    public let kind: VaultItemKind
    /// File size in bytes (0 for folders).
    public let size: Int
    /// Last modification date, if available.
    public let modificationDate: Date?
    /// Child items (non-empty only for folders).
    public let children: [VaultItem]

    /// Whether this item is a directory.
    public var isDirectory: Bool { kind == .folder }

    public init(
        url: URL,
        name: String? = nil,
        kind: VaultItemKind,
        size: Int = 0,
        modificationDate: Date? = nil,
        children: [VaultItem] = []
    ) {
        self.url = url
        self.name = name ?? url.lastPathComponent
        self.kind = kind
        self.size = size
        self.modificationDate = modificationDate
        self.children = children
    }
}

/// How to order sibling items. A small pure helper; the UI (P1.15) decides when
/// to apply it.
public enum VaultSortOrder: Sendable {
    /// Case-insensitive name, folders first.
    case name
    /// Newest modification date first, folders first.
    case modifiedDescending
}

extension VaultItem {
    /// Returns a copy of `items` sorted by `order`, recursively sorting children.
    public static func sorted(_ items: [VaultItem], by order: VaultSortOrder) -> [VaultItem] {
        let sorted = items.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory  // folders first
            }
            switch order {
            case .name:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .modifiedDescending:
                let l = lhs.modificationDate ?? .distantPast
                let r = rhs.modificationDate ?? .distantPast
                if l != r { return l > r }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
        return sorted.map { item in
            guard item.isDirectory, !item.children.isEmpty else { return item }
            return VaultItem(
                url: item.url,
                name: item.name,
                kind: item.kind,
                size: item.size,
                modificationDate: item.modificationDate,
                children: VaultItem.sorted(item.children, by: order)
            )
        }
    }
}
