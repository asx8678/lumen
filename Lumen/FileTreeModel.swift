//
//  FileTreeModel.swift
//  Lumen
//
//  Observable state + operations for the sidebar file tree (P1.15). Hosted on
//  the composition root so the File menu (P1.2) and the sidebar share one
//  selection. All filesystem work goes through the `FileService` actor (P1.5);
//  the tree refreshes by re-enumerating after each operation (live external
//  refresh is P1.6).
//

import AppKit
import LumenCore
import Observation
import os

@MainActor
@Observable
final class FileTreeModel {
    /// The sorted tree shown in the sidebar.
    private(set) var items: [VaultItem] = []

    /// The selected item's URL (file or folder).
    var selection: URL?

    /// The active sort order; changing it re-sorts the existing tree.
    var sortOrder: VaultSortOrder = .name {
        didSet { items = VaultItem.sorted(rawItems, by: sortOrder) }
    }

    /// Supplies the per-vault default new-note directory used when nothing is
    /// selected (P1.19). Wired by `AppEnvironment` to `VaultSettingsModel`.
    @ObservationIgnored var defaultNoteDirectoryProvider: (() -> URL?)?

    @ObservationIgnored private var rawItems: [VaultItem] = []
    @ObservationIgnored private let vault: VaultManager
    @ObservationIgnored private let files: FileService
    @ObservationIgnored private let logger = Logger(
        subsystem: "ai.Lumen", category: "FileTree")

    init(vault: VaultManager, files: FileService) {
        self.vault = vault
        self.files = files
    }

    /// The currently selected item, resolved from the tree.
    var selectedItem: VaultItem? {
        guard let selection else { return nil }
        return Self.find(selection, in: items)
    }

    /// The folder a create action should target (selected folder / parent of a
    /// selected file / vault root).
    var targetFolder: URL? {
        guard let root = vault.current?.root else { return nil }
        return FileTreeSupport.targetFolder(for: selectedItem, vaultRoot: root)
    }

    // MARK: - Refresh

    /// Re-enumerates the vault and rebuilds the sorted tree.
    func refresh() async {
        guard let root = vault.current?.root else {
            rawItems = []
            items = []
            return
        }
        do {
            rawItems = try await files.enumerate(root)
            items = VaultItem.sorted(rawItems, by: sortOrder)
        } catch {
            logger.error("Enumerate failed: \(String(describing: error), privacy: .public)")
            rawItems = []
            items = []
        }
    }

    // MARK: - Operations

    /// Creates a new note and selects it. With a sidebar selection it targets
    /// that folder (or a file's parent); with no selection it uses the
    /// per-vault default new-note location (P1.19), falling back to the root.
    func newNote() async {
        let dir: URL?
        if selectedItem != nil {
            dir = targetFolder
        } else {
            dir = defaultNoteDirectoryProvider?() ?? vault.current?.root
        }
        guard let dir else { return }
        await perform { try await self.files.createNote(in: dir) }
    }

    /// Creates a new folder in the target folder and selects it.
    func newFolder() async {
        guard let dir = targetFolder else { return }
        await perform { try await self.files.createFolder(in: dir) }
    }

    /// Renames the selected item.
    func rename(to newName: String) async {
        guard let url = selectedItem?.url else { return }
        await perform { try await self.files.rename(url, to: newName) }
    }

    /// Moves the selected item to the Trash.
    func delete() async {
        guard let url = selectedItem?.url else { return }
        if selection == url { selection = nil }
        do {
            try await files.moveToTrash(url)
        } catch {
            logger.error("Trash failed: \(String(describing: error), privacy: .public)")
        }
        await refresh()
    }

    /// Reveals the selected item (or the vault root) in Finder.
    func revealInFinder() {
        let url = selectedItem?.url ?? vault.current?.root
        guard let url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Private

    /// Runs an operation that yields a new URL, refreshes, and selects it.
    private func perform(_ operation: () async throws -> URL) async {
        do {
            let created = try await operation()
            await refresh()
            selection = created
        } catch {
            logger.error("File op failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Depth-first search for `url` in a tree of items.
    private static func find(_ url: URL, in items: [VaultItem]) -> VaultItem? {
        for item in items {
            if item.url == url { return item }
            if let hit = find(url, in: item.children) { return hit }
        }
        return nil
    }
}
