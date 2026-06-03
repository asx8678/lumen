//
//  TabSupport.swift
//  LumenCore
//
//  Pure, UI-agnostic helpers for the tabbed editor (P1.16): active-tab
//  reselection after a close, and vault-relative path mapping for persistence.
//  Kept here so the tricky logic is unit-testable without SwiftUI.
//

import Foundation

/// Stateless helpers for tab management.
public enum TabSupport {
    /// The index to activate after removing the tab at `index`.
    ///
    /// - Parameters:
    ///   - index: The index being removed (in the current list).
    ///   - count: The list size *before* removal.
    /// - Returns: The new active index in the post-removal list, or `nil` when
    ///   no tabs remain. Selects the tab that shifts into `index`, or the new
    ///   last tab if the removed one was last.
    public static func activeIndexAfterRemoving(_ index: Int, count: Int) -> Int? {
        let remaining = count - 1
        guard remaining > 0 else { return nil }
        return min(index, remaining - 1)
    }

    /// Maps `url` to a path relative to `root`, or `nil` if not under `root`.
    public static func relativePath(of url: URL, root: URL) -> String? {
        let rootParts = root.standardizedFileURL.pathComponents
        let urlParts = url.standardizedFileURL.pathComponents
        guard urlParts.count > rootParts.count,
            Array(urlParts.prefix(rootParts.count)) == rootParts
        else { return nil }
        return urlParts.dropFirst(rootParts.count).joined(separator: "/")
    }

    /// Resolves a vault-relative path back to an absolute URL under `root`.
    public static func resolve(relativePath: String, root: URL) -> URL {
        root.appendingPathComponent(relativePath)
    }
}
