//
//  EditorTypographyStore.swift
//  Lumen
//
//  App-level observable wrapper around `EditorTypography` (P1.13), persisted to
//  UserDefaults. The per-vault `.lumen/` config + full settings pane are P1.19;
//  this provides the live model the editor + menu commands read/write today.
//

import Foundation
import LumenEditor
import Observation

/// Observable, persisted editor typography settings.
@MainActor
@Observable
public final class EditorTypographyStore {
    private static let defaultsKey = "ai.Lumen.editorTypography"

    /// The current typography. Mutations persist automatically.
    public var typography: EditorTypography {
        didSet { persist() }
    }

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
            let decoded = try? JSONDecoder().decode(EditorTypography.self, from: data)
        {
            self.typography = decoded
        } else {
            self.typography = .default
        }
    }

    // MARK: - Mutators (used by the View ▸ Editor menu)

    public func toggleFontKind() { typography = typography.togglingFontKind() }
    public func increaseFontSize() { typography = typography.adjustingFontSize(by: 1) }
    public func decreaseFontSize() { typography = typography.adjustingFontSize(by: -1) }
    public func resetFontSize() { typography = typography.resettingFontSize() }
    public func cycleLineWidth() { typography = typography.cyclingLineWidth() }

    private func persist() {
        if let data = try? JSONEncoder().encode(typography) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
