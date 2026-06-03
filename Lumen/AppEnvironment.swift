//
//  AppEnvironment.swift
//  Lumen
//
//  The composition root: app-wide services are constructed ONCE here at launch
//  and injected down the view tree via SwiftUI `.environment` + Observation.
//  Future features (file tree P1.15, tabs P1.16, settings P1.19) read services
//  from this single object instead of re-plumbing.
//

import Foundation
import LumenCore
import LumenDesignSystem
import LumenEditor
import Observation

/// Holds the app's shared services for dependency injection.
///
/// Construct exactly one instance at app launch and inject it with
/// `.environment(_:)`. Views read individual services via the convenience
/// `@Environment` accessors below.
@MainActor
@Observable
public final class AppEnvironment {
    /// Vault open/close + recents + security-scoped access (P1.4).
    public let vault: VaultManager

    /// Off-main filesystem operations for the open vault (P1.5).
    public let files: FileService

    /// Appearance + accent theming engine (P1.17).
    public let theme: ThemeManager

    /// Adjustable, persisted editor typography (P1.13).
    public let editorTypography = EditorTypographyStore()

    /// Per-vault preferences from `.lumen/config.json` (P1.19).
    public let vaultSettings = VaultSettingsModel()

    /// The open editor tabs + active selection (P1.16).
    let tabs: TabManager

    /// Sidebar file-tree state + operations (P1.15). Hosted here so the File
    /// menu and the sidebar share one selection.
    let fileTree: FileTreeModel

    /// The FSEvents watcher for the open vault (P1.6), or `nil` when no vault.
    /// Recreated when the vault changes; its stream is consumed by
    /// reconciliation here and by the indexing actor (P1.9).
    private(set) var watcher: VaultWatcher?

    /// Observable background-indexing progress (P1.9); rendered by P1.18.
    let indexingStatus = IndexingStatus()

    /// The background indexing actor for the open vault (P1.9), or `nil`.
    private(set) var indexer: VaultIndexer?
    private var indexTask: Task<Void, Never>?

    /// Creates the composition root with fresh services. `VaultManager` reopens
    /// the last vault on launch (P1.4).
    public init() {
        let files = FileService()
        let vault = VaultManager()
        self.vault = vault
        self.files = files
        self.theme = ThemeManager()
        self.tabs = TabManager(vault: vault, files: files)
        self.fileTree = FileTreeModel(vault: vault, files: files)
        wireVaultSettings()
    }

    /// Loads the current vault's `.lumen/config.json` and routes the default
    /// new-note location into the file tree (P1.19). Call when the vault opens.
    func reloadVaultSettings() {
        vaultSettings.load(vaultRoot: vault.current?.root)
    }

    private func wireVaultSettings() {
        vaultSettings.load(vaultRoot: vault.current?.root)
        fileTree.defaultNoteDirectoryProvider = { [weak vaultSettings] in
            vaultSettings?.defaultNoteDirectory()
        }
    }

    /// The FSEvents watcher
    /// Creates the composition root with injected services (for previews/tests).
    public init(
        vault: VaultManager,
        files: FileService = FileService(),
        theme: ThemeManager? = nil
    ) {
        self.vault = vault
        self.files = files
        self.theme = theme ?? ThemeManager()
        self.tabs = TabManager(vault: vault, files: files)
        self.fileTree = FileTreeModel(vault: vault, files: files)
    }

    /// (Re)starts the FSEvents watcher for the current vault, stopping any prior
    /// one. Returns the new watcher's change stream, or `nil` when no vault is
    /// open. Driven from the root view's `.task(id: vaultRoot)`.
    func startWatching() -> AsyncStream<Set<URL>>? {
        stopWatching()
        guard let root = vault.current?.root else { return nil }
        let newWatcher = VaultWatcher(root: root)
        self.watcher = newWatcher
        let stream = newWatcher.events()

        // Start background indexing off the main thread: full index on open,
        // then incremental re-index from the watcher's own event stream (P1.9).
        if let index = try? NotesIndex(vaultRoot: root) {
            let indexer = VaultIndexer(
                root: root, files: files, index: index, status: indexingStatus)
            self.indexer = indexer
            let indexEvents = newWatcher.events()
            indexTask = Task.detached(priority: .utility) {
                await indexer.run(events: indexEvents)
            }
        }

        newWatcher.start()
        return stream
    }

    /// Stops the watcher + indexer (vault close / teardown).
    func stopWatching() {
        indexTask?.cancel()
        indexTask = nil
        indexer = nil
        watcher?.stop()
        watcher = nil
        indexingStatus.reset()
    }
}
