//
//  VaultActions.swift
//  Lumen
//
//  App-level glue for vault commands: the Open Vault… panel and the
//  File-menu commands. P1.4 scope — open/close/recents only, no file listing.
//

import AppKit
import LumenCore
import SwiftUI
import os

private let logger = Logger(subsystem: "ai.Lumen", category: "VaultActions")

/// Presents an `NSOpenPanel` to choose a folder and opens it as a vault.
@MainActor
func presentOpenVaultPanel(into manager: VaultManager) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Open Vault"
    panel.message = "Choose a folder to use as your Lumen vault."

    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
        try manager.openVault(at: url)
    } catch {
        logger.error("Open vault failed: \(String(describing: error), privacy: .public)")
        presentError(error, title: "Couldn’t Open Vault")
    }
}

/// Opens a previously-used vault from its persisted bookmark.
@MainActor
func openRecentVault(_ recent: RecentVault, into manager: VaultManager) {
    do {
        try manager.openRecent(recent)
    } catch {
        logger.error("Open recent failed: \(String(describing: error), privacy: .public)")
        presentError(error, title: "Couldn’t Open Recent Vault")
    }
}

/// Shows a simple modal alert for a vault error.
@MainActor
private func presentError(_ error: Error, title: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = (error as? VaultError).map(describe) ?? error.localizedDescription
    alert.alertStyle = .warning
    alert.runModal()
}

private func describe(_ error: VaultError) -> String {
    switch error {
    case .bookmarkCreationFailed: "Could not create a security bookmark for this folder."
    case .accessDenied: "Lumen was denied access to this folder."
    case .resolutionFailed: "This vault could not be found. It may have been moved or deleted."
    }
}

/// The File-menu commands for vault management.
struct VaultCommands: Commands {
    let manager: VaultManager

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Vault…") {
                presentOpenVaultPanel(into: manager)
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Menu("Open Recent") {
                if manager.recents.isEmpty {
                    Button("No Recent Vaults") {}
                        .disabled(true)
                } else {
                    ForEach(manager.recents) { recent in
                        Button(recent.name) {
                            openRecentVault(recent, into: manager)
                        }
                    }
                }
            }

            Button("Close Vault") {
                manager.closeVault()
            }
            .disabled(manager.current == nil)
        }
    }
}
