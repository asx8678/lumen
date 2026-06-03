//
//  EditorModePreferences.swift
//  Lumen
//
//  App-global preference (P2.2.1g) for the editing mode new tabs open in:
//  plain Source or Live Preview. Persisted to UserDefaults like the other
//  app-global ergonomics (theme P1.17, typography P1.13). The reading view is
//  never a "default editing mode" — only `.source` / `.livePreview` are valid.
//

import Foundation
import LumenCore
import Observation

/// Observable, persisted "default editing mode" for newly-opened tabs.
@MainActor
@Observable
public final class EditorModePreferences {
    private static let defaultsKey = "ai.Lumen.defaultEditingMode"

    /// The editing mode new tabs open in. Constrained to `.source` /
    /// `.livePreview`; assigning `.reading` is coerced to `.source`.
    public var defaultEditingMode: EditorViewMode {
        didSet {
            if defaultEditingMode == .reading { defaultEditingMode = .source }
            persist()
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.string(forKey: Self.defaultsKey) ?? EditorViewMode.source.rawValue
        let mode = EditorViewMode(persistedRawValue: raw)
        self.defaultEditingMode = mode.isEditing ? mode : .source
    }

    private func persist() {
        defaults.set(defaultEditingMode.rawValue, forKey: Self.defaultsKey)
    }
}
