//
//  ReadingCommands.swift
//  Lumen
//
//  The View ▸ Toggle Reading View command (P2.1.1), bound to ⌘E to match the
//  Obsidian muscle-memory Lumen emulates. Flips the active tab between the
//  editable source and the rendered, read-only reading view; the mode is
//  per-tab and persisted with the tab set.
//

import LumenCore
import SwiftUI

/// Adds View ▸ Toggle Reading View (⌘E) to the standard View menu.
struct ReadingCommands: Commands {
    let env: AppEnvironment

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button(readingLabel) { env.tabs.toggleActiveReadingView() }
                .keyboardShortcut("e", modifiers: [.command])
                .disabled(env.tabs.active == nil)

            Button(livePreviewLabel) { env.tabs.toggleActiveEditingMode() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(env.tabs.active == nil)
        }
    }

    private var readingLabel: String {
        env.tabs.active?.viewMode == .reading ? "Show Editor" : "Toggle Reading View"
    }

    /// Reflects which editing mode ⇧⌘E will switch *to* (Source ⇄ Live Preview).
    private var livePreviewLabel: String {
        env.tabs.active?.viewMode == .livePreview
            ? "Switch to Source" : "Switch to Live Preview"
    }
}
