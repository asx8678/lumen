//
//  FileTreeSupport.swift
//  LumenCore
//
//  Pure, UI-agnostic helpers for the file-tree view (P1.15): resolving which
//  folder a "New Note / New Folder" action should target given the current
//  selection. Kept here so it is unit-testable.
//

import Foundation

/// Helpers for file-tree actions.
public enum FileTreeSupport {
    /// Resolves the directory a create action should target.
    ///
    /// - If a folder is selected, create inside it.
    /// - If a file is selected, create alongside it (its parent directory).
    /// - If nothing is selected, create in the vault root.
    ///
    /// - Parameters:
    ///   - selection: The selected item, if any.
    ///   - vaultRoot: The vault's root directory (fallback).
    /// - Returns: The directory URL to create the new item in.
    public static func targetFolder(for selection: VaultItem?, vaultRoot: URL) -> URL {
        guard let selection else { return vaultRoot }
        switch selection.kind {
        case .folder:
            return selection.url
        case .markdown, .other:
            return selection.url.deletingLastPathComponent()
        }
    }
}
