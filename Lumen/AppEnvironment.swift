//
//  AppEnvironment.swift
//  Lumen
//
//  The composition root: app-wide services are constructed ONCE here at launch
//  and injected down the view tree via SwiftUI `.environment` + Observation.
//  Future features (file tree P1.15, tabs P1.16, settings P1.19) read services
//  from this single object instead of re-plumbing.
//

import LumenCore
import LumenDesignSystem
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

    /// The open editor tabs + active selection (P1.16).
    let tabs: TabManager

    /// Sidebar file-tree state + operations (P1.15). Hosted here so the File
    /// menu and the sidebar share one selection.
    let fileTree: FileTreeModel

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
    }

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
}
