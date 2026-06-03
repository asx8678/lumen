//
//  EditorViewMode.swift
//  LumenCore
//
//  The per-tab presentation mode (P2.1.1): the live Markdown editor, or the
//  rendered, read-only reading view. Held per-`DocumentSession` so each tab
//  remembers its own mode, and persisted with the tab set so it survives
//  relaunch (defaults to `.edit` for new/legacy tabs).
//

import Foundation

/// How a tab presents its document: editable source, or rendered reading view.
public enum EditorViewMode: String, Sendable, Codable, CaseIterable, Equatable {
    /// The live, editable Markdown source (the TextKit 2 editor).
    case edit
    /// The rendered, read-only reading view.
    case reading

    /// The opposite mode (used by the ⌘E toggle).
    public var toggled: EditorViewMode {
        self == .edit ? .reading : .edit
    }
}
