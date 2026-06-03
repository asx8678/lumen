//
//  EditorViewMode.swift
//  LumenCore
//
//  The per-tab presentation mode (P2.1.1 → P2.2.1g). A tab is shown in one of
//  three modes: the plain editable **source**, the editable source with live
//  **livePreview** decorations active, or the rendered, read-only **reading**
//  view. Held per-`DocumentSession` so each tab remembers its own mode, and
//  persisted with the tab set so it survives relaunch.
//
//  Back-compat: legacy snapshots stored only `edit`/`reading`. `edit` decodes
//  to `.source` and `reading` to `.reading`, so older tab sets restore cleanly.
//

import Foundation

/// How a tab presents its document.
public enum EditorViewMode: String, Sendable, Codable, CaseIterable, Equatable {
    /// The live, editable Markdown source with no live-preview decorations
    /// (the shipping Phase-1 editor behavior).
    case source
    /// The editable Markdown source with live-preview decorations active
    /// (S-class concealment, block chrome, W-class widgets).
    case livePreview
    /// The rendered, read-only reading view.
    case reading

    /// Decodes a single string value, mapping the legacy `"edit"` raw value to
    /// `.source` so pre-P2.2.1g snapshots restore cleanly. The synthesized
    /// `encode(to:)` continues to write the current raw values.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = EditorViewMode(persistedRawValue: raw)
    }

    /// Maps a persisted raw value — including the legacy `"edit"` — to a mode,
    /// defaulting to `.source` for anything unrecognized.
    public init(persistedRawValue raw: String) {
        switch raw {
        case "edit", "source": self = .source
        case "livePreview": self = .livePreview
        case "reading": self = .reading
        default: self = .source
        }
    }

    /// Whether this is an editing mode (`source`/`livePreview`) as opposed to
    /// the read-only reading view.
    public var isEditing: Bool { self != .reading }

    /// The other editing mode (`source` ⇄ `livePreview`). Reading maps to
    /// `source` so a toggle from reading lands somewhere sensible.
    public var toggledEditingMode: EditorViewMode {
        switch self {
        case .source: return .livePreview
        case .livePreview, .reading: return .source
        }
    }
}
